# Dashboard · Liquidity Projection · Agent Insights

## Contexto y motivación

El dashboard actual tiene dos fallas críticas:

1. **Cash flow ciego** — El sistema puede recomendar abonar dinero a deuda sin considerar que hay obligaciones del próximo ciclo que cubrir. Ejemplo: "tienes $4M de surplus, págalos al CrediExpress" cuando hay $5M de obligaciones el 15 del mes siguiente y solo llegan $3M de ingreso temprano. El usuario queda sin flujo de caja.

2. **Métricas confusas** — El hero card mostraba `-$2,458,138 disponible` usando solo el ingreso base como denominador, ignorando el ingreso variable confirmado. Al mismo tiempo mostraba overflow disponible. Contradicción directa.

## Principio de diseño

El sistema se comporta como un contador personal responsable:
- Nunca recomienda desplegar dinero que ya está comprometido con obligaciones del próximo ciclo.
- Muestra el **superávit no asignado** (dinero que sobró después de cubrir todo lo comprometido) como primera verdad.
- Las recomendaciones estratégicas (dónde poner el superávit) vienen del agente, no de un algoritmo frágil.
- Calidad de vida y flujo de caja tienen prioridad sobre objetivos de deuda.

## Guardrail fundamental

```
safe_to_deploy = max(0,
  projected_eom_balance
  - next_cycle_gap
  - protected_buffer
)

next_cycle_gap          = max(0, next_cycle_obligations - early_next_month_income)
next_cycle_obligations  = recurring_obligations_total + debt_minimums_total
early_next_month_income = sum(income_sources donde expected_day_from <= 15 del mes siguiente)
projected_eom_balance   = confirmed_balance + pending_income
pending_income          = ingresos variables de income_sources aún no confirmados este mes
```

**Ninguna recomendación puede superar `safe_to_deploy`.** Si es $0, el mensaje es "Cubre tus obligaciones del próximo ciclo primero."

---

## FASE 1 — Backend numérico

### 1.1 Fix burn_rate aggregation ✅
**Archivo:** `app/controllers/api/v1/summary_controller.rb`

**Problema:** `build_burn_rate` iteraba sobre budgets crudos (uno por subcategoría) y comparaba el `amount_limit` de cada subcategoría contra el gasto total de la categoría entera. Producía porcentajes absurdos (8269%).

**Fix:** Agrupar budgets por `category_id` sumando `amount_limit` antes del map. Una fila por categoría con el presupuesto real agregado.

---

### 1.2 Interactor `LiquidityProjection` ✅
**Archivo:** `app/domains/finanzas/interactors/liquidity_projection.rb`

**Output:**
```ruby
{
  confirmed_balance:      Integer,
  pending_income:         Integer,
  projected_eom_balance:  Integer,
  next_cycle_obligations: Integer,
  protected_buffer:       Integer,
  free_after_obligations: Integer,
  safe_to_deploy:         Integer,
  buffer_status:          "critical" | "tight" | "comfortable"
}
```

Integrado en `GET /api/v1/summary` como campo `liquidity`.

**Limitación conocida:** `pending_income` actualmente usa `max(0, planned_total - income_confirmed)`. Se rompe cuando `income_confirmed > planned_total` por ajustes de saldo inicial o ingresos atípicos. Ver 1.3.

---

### 1.3 Fix `pending_income` en LiquidityProjection ✅
**Archivo:** `app/domains/finanzas/interactors/liquidity_projection.rb`

**Problema:** La fórmula actual da $0 cuando el income confirmado ya supera el total planeado, aunque haya ingresos variables que aún no llegaron.

**Fix:** El interactor recibe `income_sources` desde el controller y calcula:
```ruby
pending_income = income_sources
  .select { |s| s[:classification] == "variable" && s[:active] }
  .reject { |s| already_confirmed_this_month?(s, confirmed_income_transactions) }
  .sum { |s| s[:expected_amount] }
```

Requiere que el `SummaryController` cargue `income_sources` y los pase al interactor. Una query adicional.

---

### 1.4 Integrar `safe_to_deploy` como guardrail en recomendaciones ✅
**Archivo:** `app/controllers/api/v1/summary_controller.rb`

**Cambio:** `build_recommended_action` recibe `safe_to_deploy` de `LiquidityProjection` y lo usa como techo del abono recomendado. Si `safe_to_deploy == 0`, la recomendación es "Cubre tus obligaciones del próximo ciclo primero. No hay margen para mover."

```ruby
def build_recommended_action(ctx, active_debts, safe_to_deploy)
  return "Cubre tus obligaciones del próximo ciclo primero." if safe_to_deploy <= 0
  abono = [safe_to_deploy, target[:current_balance]].min
  ...
end
```

---

## FASE 2 — Frontend dashboard restructurado

### 2.1 Tipos TypeScript ✅
**Archivo:** `src/types/finance.types.ts`

Nueva interface:
```typescript
export interface LiquidityProjection {
  confirmed_balance: number;
  pending_income: number;
  projected_eom_balance: number;
  next_cycle_obligations: number;
  protected_buffer: number;
  free_after_obligations: number;
  safe_to_deploy: number;
  buffer_status: 'critical' | 'tight' | 'comfortable';
}
```

Agregar campo opcional a `SummaryResponse`:
```typescript
liquidity?: LiquidityProjection | null;
```

---

### 2.2 Instalar recharts ✅
```bash
npm install recharts
```
Verificar que no conflictúe con el bundle de Ionic antes de usarlo en componentes.

---

### 2.3 Restructurar DashboardPage ✅
**Archivo:** `src/components/pages/DashboardPage/DashboardPage.tsx`

**Tres zonas:**

**Zona 1 — Hero (siempre visible)**
- Pregunta: "¿Cuánto puedo mover este mes?"
- Valor principal: `liquidity.safe_to_deploy`
- Barra de presión: `next_cycle_obligations` vs `projected_eom_balance`
- Mensaje contextual según `buffer_status`
- Recomendación: viene de `agent_insights` (Fase 3). Fallback temporal: `financial_context.recommended_action`

**Zona 2 — Snapshot (visible por defecto, colapsable)**
- 3 KPIs en fila: balance hoy · ingreso pendiente · reservado próximo ciclo
- Donut chart: distribución de gastos del mes por categoría (5 categorías, colores del sistema)
- Bar chart horizontal: burn rate por categoría — presupuestado vs gastado

**Zona 3 — Detalle (detrás de "Ver detalle")**
- Tabla de pendientes
- Tabla de obligaciones próximo ciclo
- Tabla de deudas activas

Los 6 metricCards actuales se eliminan — su información queda absorbida en las zonas nuevas.

---

### 2.4 Estilos DashboardPage ✅
**Archivo:** `src/components/pages/DashboardPage/DashboardPage.module.css`

Clases nuevas: `heroCard`, `heroValue`, `pressureBar`, `pressureBarFill`, `kpiRow`, `kpiBlock`, `chartPanel`. Reutilizar clases existentes de `FinancePage.module.css` donde aplique.

---

## FASE 3 — Agent Insights (recomendaciones diarias con guard)

### Principio
El agente corre diariamente pero solo actualiza recomendaciones cuando el estado financiero ha derivado materialmente. Esto separa el razonamiento (agente) del cálculo numérico (API), y evita recomendar estrategias que ignoren el flujo de caja real.

**Modelos:**
- Drift checker: Ruby puro, $0
- Evaluación de vigencia del insight anterior: Haiku (~$0.001/corrida)
- Generación de nuevo insight: Sonnet (~$0.01-0.02/corrida, ~4-6 veces/mes)

---

### 3.1 Migración `agent_insights` ⬜
**Repo:** daniel15k-api

```ruby
create_table :agent_insights do |t|
  t.references :account, null: false, foreign_key: true
  t.integer    :period_month, null: false
  t.integer    :period_year,  null: false
  t.datetime   :generated_at, null: false
  t.jsonb      :key_metrics_snapshot, default: {}
  t.jsonb      :recommendations,      default: {}
  t.text       :reasoning
  t.jsonb      :signals,              default: []
  t.integer    :safe_to_deploy_amount
  t.string     :trigger_reason  # "month_change" | "balance_drift" | "manual" | "initial"
  t.timestamps
end

add_index :agent_insights, [:account_id, :period_year, :period_month],
          name: "index_agent_insights_on_account_period"
```

---

### 3.2 Endpoints API ⬜
**Archivo:** `app/controllers/api/v1/agent_insights_controller.rb`

- `GET /api/v1/agent_insights/current?month=&year=` — devuelve el insight vigente del período
- `POST /api/v1/agent_insights` — persiste el output del agente (requiere service token)

---

### 3.3 Interactor `InsightDriftChecker` ⬜
**Archivo:** `app/domains/finanzas/interactors/insight_drift_checker.rb`

Ruby puro, sin LLM. Recibe estado actual + insight anterior, retorna `{ should_refresh: bool, reason: string }`.

Reglas de refresh:
```ruby
return { should_refresh: true, reason: "initial" }       if last_insight.nil?
return { should_refresh: true, reason: "month_change" }   if month_changed?
return { should_refresh: true, reason: "balance_drift" }  if balance_drift > 1_000_000
return { should_refresh: true, reason: "track_change" }   if on_track_status_changed?
return { should_refresh: true, reason: "deploy_drift" }   if safe_to_deploy_drift > 500_000
{ should_refresh: false, reason: "stable" }
```

---

### 3.4 Skill del agente `generate_insight` ⬜
**Repo:** daniel15k-agents

Recibe: summary completo + liquidity + insight anterior.

El prompt incluye explícitamente:
- El guardrail: "Nunca recomiendes desplegar más de `safe_to_deploy`. Si es $0, las obligaciones van primero."
- La evaluación de vigencia: "¿El insight anterior sigue siendo válido dado el estado actual? Si sí, confirma sin cambiar. Si no, genera uno nuevo."
- Prioridad: flujo de caja y calidad de vida > objetivos de deuda > metas de ahorro.

Output estructurado:
```json
{
  "still_valid": false,
  "recommendations": {
    "primary_action": "...",
    "safe_to_deploy_suggested": 2000000,
    "rationale": "..."
  },
  "signals": [
    { "type": "warn", "category": "social", "message": "..." }
  ],
  "reasoning": "Texto completo del razonamiento del agente."
}
```

---

### 3.5 Cron job diario ⬜
**Repo:** daniel15k-agents

Hora: 2am Colombia (UTC-5 → 7am UTC)

```
Para cada cuenta activa:
  1. GET /api/v1/summary + /api/v1/agent_insights/current
  2. InsightDriftChecker (Ruby, $0)
  3. Si should_refresh:
       → Haiku: "¿El insight anterior sigue válido?"
       → Si no: Sonnet ejecuta generate_insight
       → POST /api/v1/agent_insights con resultado
  4. Si stable: skip
```

---

### 3.6 UI consume agent_insights ⬜
**Archivo:** `src/components/pages/DashboardPage/DashboardPage.tsx`

La recomendación en Zona 1 (Hero) viene de `agent_insights.recommendations.primary_action`.

Estados posibles:
- Insight vigente: muestra recomendación + badge "Evaluado hace N días"
- Sin insight aún: muestra `financial_context.recommended_action` con badge "Estimado"
- Insight vencido (> 7 días): muestra "Análisis en proceso" sin recomendación de acción

Botón "Actualizar análisis" disponible → dispara cron on-demand con rate limiting (máx 1 vez cada 6h por cuenta).

---

## Orden de ejecución

```
1.3 → 1.4 → 2.1 → 2.2 → 2.3 → 2.4 → 3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6
```

Las fases 1 y 2 son independientes de la 3. El dashboard puede lanzarse con fallback a `financial_context.recommended_action` mientras la Fase 3 no esté lista. Cuando esté, la UI hace el swap a `agent_insights`.
