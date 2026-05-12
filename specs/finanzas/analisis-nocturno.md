# Análisis Nocturno — Coach con Contexto

> Estado: 🟢 activo — pendiente de implementación
> Última actualización: 2026-05-12
> Reemplaza: la Fase 3 de `dashboard.md` (esquema `agent_insights` mensual plano)
> Depende de: `cash-flow-runway.md`, `capa-conductual.md`, `domain-agent-delegation.md`

---

## Principio rector

El agente no es una calculadora que genera texto. Es un coach que interpreta
señales ya procesadas. La API hace el trabajo numérico; el agente aporta
criterio, contexto y humanidad.

**El dato frío siempre necesita revisión.** Un gasto de $2.5M puede ser
el arriendo mensual esperado (no hay nada que decir) o una compra discrecional
anómala (hay mucho que decir). El sistema tiene que distinguirlos antes de
que el agente los vea. Si el agente recibe el dato crudo, su única opción
es asustarse — y un agente paranoico destruye la confianza del usuario.

---

## Por qué el esquema anterior no servía

`agent_insights` era una tabla mensual plana:
- Un registro por mes por cuenta, sobreescrito cada noche
- Sin historia: no podías ver qué dijo el agente el martes pasado
- Sin tap-through: el insight era solo texto, no tenía métricas asociadas
- Sin tipos: el mismo blob jsonb intentaba servir para cualquier cadencia
- `safe_to_deploy_amount` hardcodeado como columna a pesar de que ese
  concepto ya fue reemplazado por `cash_flow_runway`

---

## Arquitectura nueva

### Separación de responsabilidades

```
NightAnalysis            ← los hechos de esta noche, ya contextualizados
    │
    └── AgentInsight     ← lo que el agente dijo sobre esos hechos
            │
            └── Frontend ← la card del dashboard + la pantalla de detalle
```

`NightAnalysis` es el registro estadístico. `AgentInsight` es el registro
de coaching. Son entidades distintas unidas por asociación polimórfica.

---

## Esquema de base de datos

### `night_analyses`

```ruby
create_table :night_analyses do |t|
  t.references :account,             null: false, foreign_key: true
  t.date       :analysis_date,       null: false
  t.string     :health_status,       null: false   # comfortable | warning | critical

  # Métricas de flujo — del CashFlowRunway de esa noche
  t.integer    :commitment_gap,      null: false
  t.integer    :daily_burn,          null: false
  t.integer    :days_to_next_income

  # Señales conductuales — ya filtradas y contextualizadas
  t.jsonb      :category_alerts,     null: false, default: []
  # [{category_type, spent, budget, pct_used, vs_rolling_avg_pct, status}]

  t.jsonb      :transactions_context, null: false, default: {}
  # {
  #   matched:   [{tx_id, amount, obligation_name, expected_amount, delta}],
  #   unmatched: [{tx_id, amount, concept, category_type}]
  # }
  # "matched" = transacciones que corresponden a una recurring_obligation conocida
  # "unmatched" = lo que el agente realmente necesita revisar

  t.jsonb      :burn_vs_plan,        null: false, default: []
  # [{category_type, spent, budget, pct, vs_rolling_avg_pct}]

  t.text       :agent_reasoning
  # El razonamiento completo del agente para esta noche — texto libre,
  # no estructurado. Para mostrar en la pantalla de detalle.

  t.timestamps
end

add_index :night_analyses, [:account_id, :analysis_date],
          unique: true,
          name: "index_night_analyses_on_account_and_date"
```

### `agent_insights` (rediseño)

```ruby
create_table :agent_insights do |t|
  t.references :account,         null: false, foreign_key: true
  t.references :insightable,     polymorphic: true, null: false
  # insightable_type: "NightAnalysis" | "WeeklyAnalysis" | "MonthlyAnalysis"

  t.string  :insight_kind,       null: false
  # tip | congratulation | alert | proposal | achievement

  t.string  :title,              null: false
  t.text    :body,               null: false

  t.string  :status,             null: false, default: "new"
  # new | seen | actioned | dismissed

  t.datetime :generated_at,      null: false
  t.timestamps
end

add_index :agent_insights, [:account_id, :status],
          name: "index_agent_insights_on_account_and_status"
add_index :agent_insights, [:insightable_type, :insightable_id],
          name: "index_agent_insights_on_insightable"
```

**Por qué polimórfico:** cada cadencia de análisis tiene métricas
fundamentalmente distintas. `NightAnalysis` tiene `daily_burn` y
`transactions_context`. Un futuro `MonthlyAnalysis` tendrá
`savings_rate`, `plan_execution_accuracy`, `income_realization_pct`.
Forzarlos en una sola tabla jsonb es inmantenible y no consultable.

---

## La capa de pre-contextualización

Este es el trabajo que hace la API antes de que el agente vea cualquier dato.

### `build_night_metrics` — lo que el tool devuelve al agente

```ruby
# app/domains/finanzas/interactors/build_night_metrics.rb

{
  # Estado de flujo — ya calculado por CashFlowRunway
  health_status:        "comfortable" | "warning" | "critical",
  commitment_gap:       Integer,
  daily_burn:           Integer,
  days_to_next_income:  Integer,

  # Señales conductuales por gaveta — vs su propio historial, no vs cero
  category_alerts: [
    {
      category_type:       "discretionary",
      spent:               1_200_000,
      budget:              1_500_000,
      pct_used:            80,
      vs_rolling_avg_pct:  +12,   # está gastando 12% más que su promedio
      status:              "on_track" | "near_limit" | "over"
    }
  ],

  # Transacciones de hoy, ya clasificadas
  transactions_context: {
    matched: [
      # Estas transacciones coinciden con una recurring_obligation conocida.
      # El agente NO necesita alarmarse por ellas — son esperadas.
      {
        tx_id:             42,
        amount:            2_500_000,
        obligation_name:   "Arriendo",
        expected_amount:   2_450_000,
        delta:             50_000     # pagó $50k más de lo esperado
      }
    ],
    unmatched: [
      # Solo esto necesita análisis real del agente.
      {
        tx_id:        43,
        amount:       380_000,
        concept:      "Restaurante La Barra",
        category_type: "discretionary"
      }
    ]
  },

  # Comparación burn vs plan por gaveta — para contextualizar patrones
  burn_vs_plan: [
    {
      category_type:      "necessary",
      spent:              850_000,
      budget:             1_200_000,
      pct:                71,
      vs_rolling_avg_pct: -8     # está gastando 8% menos que su promedio
    }
  ]
}
```

**Regla de oro del tool:** si una transacción matchea una
`recurring_obligation` activa con `abs(delta) < 5%`, va a `matched` y
el agente no la ve en `unmatched`. El ruido desaparece antes de llegar
al razonamiento.

La lógica de matching reutiliza `DetectTransactionStructure` que ya existe.

---

## Diseño del agente

### Secuencia de la noche

```
1. Tool: get_night_metrics(account_id, date)
   → Recibe las métricas ya contextualizadas

2. Tool: get_user_context(account_id)
   → Recibe perfil del usuario:
     - income_sources (montos, días esperados)
     - recurring_obligations activas
     - nivel del sistema (gamification)
     - plan mensual activo (gavetas y presupuestos)
     - historial de insights anteriores (últimos 7 días)

3. Razonamiento del agente
   → Con ese contexto, evalúa:
     - ¿Hay algo en unmatched que amerite coaching?
     - ¿Alguna gaveta muestra un patrón preocupante (no solo un día)?
     - ¿El health_status es peor que ayer? ¿Es estructural o puntual?
     - ¿Hay algo positivo que merece refuerzo?

4. Tool: create_night_analysis(metrics, insight_kind, title, body, reasoning)
   → Crea NightAnalysis + AgentInsight en una sola transacción atómica
   → El agente no maneja IDs ni asociaciones — eso es plomería de la API
```

### Lo que el prompt le garantiza al agente

```
CONTEXTO PRIMERO, NÚMEROS DESPUÉS.

Antes de interpretar cualquier número, tienes:
- El perfil completo del usuario (qué tiene comprometido, cuándo llega su ingreso)
- Las transacciones de hoy ya clasificadas: "matched" son esperadas, no las analices
- Solo "unmatched" y las señales de categoría requieren tu criterio real

COACHING, NO ALARMA.

Un gasto en "matched" no es una alerta — es el sistema funcionando bien.
Una gaveta al 80% no es una crisis — revisa si está dentro de su promedio histórico.
Tu función es ayudar al usuario a entender sus patrones, no asustarlo.

TONO SEGÚN NIVEL.

Nivel 0-1: simple y directo, sin jerga financiera.
Nivel 2-3: más profundidad, empieza a introducir conceptos.
Nivel 4-5: peer-to-peer, el usuario ya sabe lo que hace.
```

---

## API

### `POST /api/v1/night_analyses`
Requiere: service token + scope `agent:write`

El agente envía un payload único. La API crea `NightAnalysis` +
`AgentInsight` en una transacción. El agente nunca gestiona IDs ni
asociaciones polimórficas.

```json
{
  "account_id": 1,
  "analysis_date": "2026-05-12",
  "metrics": { ...output de build_night_metrics... },
  "agent_reasoning": "Texto libre del razonamiento del agente...",
  "insight": {
    "kind": "tip",
    "title": "Discretionary va bien este mes",
    "body": "Gastaste $380k hoy en restaurante pero sigues 8% por debajo de tu promedio. Sin alarmas."
  }
}
```

### `GET /api/v1/night_analyses/:date`
Requiere: JWT de usuario

Devuelve el `NightAnalysis` del día con su `AgentInsight` incluido.
Usado por la pantalla de detalle nocturno.

### `GET /api/v1/agent_insights/latest`
Requiere: JWT de usuario

Devuelve el `AgentInsight` más reciente con `status != dismissed`.
Usado por la card del dashboard.

### `PATCH /api/v1/agent_insights/:id`
Requiere: JWT de usuario

Actualiza `status` a `seen`, `actioned`, o `dismissed`.

### `GET /api/v1/night_analyses` (colección)
Requiere: JWT de usuario

Historial paginado de análisis nocturnos. Para la pantalla de historial
(futura). Parámetros: `from_date`, `to_date`, `per_page`.

---

## Frontend

### Card del dashboard (ya existe, actualizar)

La card de insight en el dashboard actualmente muestra
`insight?.recommendations?.primary_action`. Debe migrar a:
- Título del `AgentInsight` más reciente
- Cuerpo (truncado a 2 líneas)
- `insight_kind` para el ícono y color de acento
- Badge: "Análisis de anoche · [fecha]"
- Tap → navega a `/analisis/:date`

Estados:
- `new` → dot de notificación en el FAB del agente
- `seen` → card normal sin dot
- `dismissed` → no aparece, muestra la siguiente

### Pantalla de detalle `/analisis/:date`

Misma filosofía que `BudgetDetailPage`: `IonPage` standalone, sin
`AppLayout`, topbar propio.

Secciones:
1. **Estado de esa noche** — `health_status` con color conductual,
   `commitment_gap`, `days_to_next_income`
2. **Lo que el agente revisó** — lista de `unmatched` transactions
   con el contexto de categoría
3. **Cómo van tus gavetas** — `burn_vs_plan` con barras de presión
4. **Lo que el agente dijo** — `agent_reasoning` completo en texto,
   con el insight destacado arriba
5. **Transacciones esperadas** — `matched` en una lista colapsable
   titulada "Movimientos conocidos" — el usuario puede verificar

---

## Guard de drift (simplificado)

El `InsightDriftChecker` existente sigue siendo válido como guardia
para no regenerar insights triviales. En el contexto nuevo:

```ruby
# Solo regenera si hay cambio material desde el último análisis nocturno
def should_run_tonight?(last_analysis, current_metrics)
  return true if last_analysis.nil?
  return true if last_analysis.analysis_date < Date.today  # nunca hay dos por día

  false  # ya corrió hoy
end
```

Para el análisis nocturno la pregunta es simple: ¿corrió hoy? Si no,
corre. El drift checker complejo era necesario para el esquema mensual
donde el mismo registro se sobreescribía. Con registros diarios
independientes no hay ambigüedad.

---

## Orden de implementación

```
Fase 1 — Backend
  1. Migración: crear night_analyses + rediseñar agent_insights
  2. Modelos Rails (NightAnalysis, AgentInsight con polymorphic)
  3. Interactor BuildNightMetrics (pre-contextualización)
  4. Repositorios: NightAnalysisRepository, AgentInsightRepository
  5. Endpoints: POST /night_analyses, GET /night_analyses/:date,
                GET /agent_insights/latest, PATCH /agent_insights/:id

Fase 2 — Agente
  6. Tool get_night_metrics (llama BuildNightMetrics)
  7. Tool get_user_context (perfil + plan + historial insights)
  8. Tool create_night_analysis (escritura atómica)
  9. Refactor nightly.py para usar los 3 tools nuevos
  10. Prompt nocturno con sección de contexto primero

Fase 3 — Frontend
  11. Migrar card del dashboard al nuevo AgentInsight
  12. Pantalla /analisis/:date (NightAnalysisDetailPage)
  13. Mark as seen al abrir el detalle (PATCH status → seen)
  14. Dot de notificación en FloatingAgent cuando hay insight new
```

---

## Lo que NO cambia

- El modelo de `cash_flow_runway` — es la fuente de verdad del flujo.
  `BuildNightMetrics` lo consume, no lo reemplaza.
- La arquitectura polimórfica de `account_id` y service tokens.
- `DetectTransactionStructure` — se reutiliza para el matching de
  transacciones vs obligaciones en la capa de pre-contextualización.
- La gamificación: el nightly review sigue desbloqueándose en Nivel 2.
  Lo que cambia es que ahora tiene pantalla de detalle real.

---

## Qué queda para cadencias futuras

`WeeklyAnalysis`, `MonthlyAnalysis`, `YearAnalysis` seguirán el mismo
patrón: tabla propia con métricas específicas de esa cadencia, ligada
a `AgentInsight` vía polimorfismo. Cuando llegue el momento, el esquema
ya está preparado para recibirlos sin cambios estructurales.
