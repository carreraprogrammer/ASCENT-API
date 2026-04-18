# Módulo de Presupuesto — Plan de Implementación

> Framework: Zero-Based Budgeting (ZBB)
> Fase objetivo inicial: `debt_payoff` con estrategia snowball
> Última actualización: 2026-04-18

---

## 1. Marco conceptual

**¿Por qué Zero-Based Budgeting?**
En ZBB cada peso del ingreso tiene destino asignado. El resultado siempre es cero — no hay dinero "flotando". Es el único framework que funciona correctamente en fase `debt_payoff` porque fuerza la decisión explícita de qué hacer con cada excedente. Fuentes: Monarch Money (2023), YNAB methodology, Ramsey Solutions debt snowball framework.

**Regla de adaptación por fase:**
Las categorías de ahorro y pago de deudas NO son obligatorias universalmente. Su obligatoriedad depende de la fase financiera del usuario (`financial_context.phase`):

| Fase | `debt_payoff` obligatorio | `savings_buffer` obligatorio |
|------|--------------------------|------------------------------|
| `debt_payoff` | Sí (mínimos + snowball) | No (contraproducente salvo emergencia mínima) |
| `emergency_fund` | Solo mínimos | Sí |
| `investing` | Solo mínimos | Sí |
| `wealth_building` | No (si ya está liquidado) | Sí |

Un usuario en `debt_payoff` sin fondo de emergencia puede legítimamente tener `savings_buffer: 0`. El sistema lo permite y solo muestra una advertencia contextual, no un bloqueo.

---

## 2. Datos requeridos para calcular un presupuesto

En orden de prioridad:

1. **`income_sources` con `classification: 'fixed'`** — entra al `base_budget_income`. Sin esto no hay presupuesto.
2. **`income_sources` con `classification: 'variable'`** — proyección conservadora: `amount × (reliability_score / 100)`. Nunca se planifica como ingreso garantizado. Se reporta como "si entra, va a X".
3. **`recurring_obligations` activos con `budget_category` asignado** — la base de gastos comprometidos.
4. **`debts` activos con `monthly_payment`** — los mínimos son obligaciones no negociables en cualquier fase.
5. **`financial_context`** — `phase`, `strategy`, `reward_pct` determinan cómo se distribuye el margen libre.

---

## 3. Categorías del sistema (9 base, inmutables)

El usuario puede agregar categorías custom, pero no puede eliminar estas 9. El sistema las usa para calcular el plan y mapear transacciones.

| Código | Nombre display | Tipo ZBB | Obligatoria |
|--------|---------------|----------|-------------|
| `housing` | Vivienda | Committed | Siempre |
| `utilities` | Servicios públicos y digital | Committed | Siempre |
| `groceries` | Mercado y alimentación | Necessary | Siempre |
| `transportation` | Transporte | Necessary | Siempre |
| `health` | Salud | Necessary | Siempre |
| `debt_payoff` | Pago de deudas | Committed | Solo si hay deudas activas |
| `dining_leisure` | Ocio y restaurantes | Discretionary | No (puede ser $0) |
| `personal_care` | Cuidado personal | Discretionary | No (puede ser $0) |
| `savings_buffer` | Ahorro / buffer emergencia | Investment | Depende de la fase (ver tabla sección 1) |

**Regla de display:** Las categorías con monto $0 no se ocultan — se muestran con estado "sin asignar" para que el usuario sea consciente de la decisión.

---

## 4. Mapeo recurring_obligations → budget_category

**Fuente de verdad única: `recurring_obligations`.**

El campo `budget_category` en `recurring_obligations` determina a qué categoría del presupuesto pertenece cada gasto fijo. No se ingresa el monto en el presupuesto manualmente — se calcula automáticamente.

```
recurring_obligation.budget_category = 'housing'  →  plan.housing_total += amount
recurring_obligation.budget_category = 'utilities' →  plan.utilities_total += amount
```

**Ejemplos de mapeo:**

| Gasto recurrente | budget_category |
|-----------------|-----------------|
| Arriendo | `housing` |
| Administración edificio | `housing` |
| Energía eléctrica | `utilities` |
| Agua | `utilities` |
| Internet / fibra | `utilities` |
| Celular (plan) | `utilities` |
| Netflix, Spotify, YouTube Premium | `dining_leisure` |
| GitHub, Railway, herramientas dev | `utilities` (si es trabajo) o `personal_care` |
| Gimnasio / boxeo | `personal_care` |
| Seguro médico | `health` |
| Cuotas de deuda | **NO van aquí** — vienen de `debts.monthly_payment` directamente |

**Regla de validación:** No se puede crear ni activar una `recurring_obligation` sin `budget_category`. El sistema lo requiere.

**Prevención de duplicación:** Las cuotas de deuda (`debts.monthly_payment`) nunca se registran como `recurring_obligation`. Son una línea separada en el plan. Si el usuario intenta crearla como obligación recurrente, el sistema muestra: *"Esto parece una cuota de deuda. ¿Querés registrarla en la sección Deudas para llevar el saldo correctamente?"*

---

## 5. Fases de creación del presupuesto

### Fase 0 — Preflight (automático, sin interacción)

El sistema evalúa si hay suficientes datos antes de invocar al agente.

**Si falta `income_sources`:** No se abre el wizard de presupuesto. El `CompletenessIndicator` muestra `income_profile` como prerequisito bloqueante (ya implementado con `dependsOn`). Se abre el wizard de ingresos primero.

**Si falta `recurring_obligations`:** Se continúa pero el plan se marca como `provisional`. Se muestra advertencia: *"Sin gastos fijos registrados, el margen libre está inflado. ¿Querés agregar arriendo, servicios, suscripciones antes de continuar?"* con opción de continuar de todas formas.

**Si el plan del mes ya existe con `status: confirmed`:** No se invoca al agente. Se muestra el plan guardado directamente con opción de "Recalcular" si el usuario quiere actualizarlo.

**Si el plan del mes ya existe con `status: draft`:** Se muestra el borrador con la propuesta del agente y se pregunta si quiere confirmarlo o recalcular.

### Fase 1 — Contexto al agente (sin tool calls de datos)

`WebChatJob` pre-fetcha `GET /api/v1/budget_context` antes de llamar al Brain. Este endpoint devuelve todo en un solo request:
- Income sources clasificados con proyección conservadora del variable
- Recurring obligations agrupados por `budget_category`
- Debt minimums totalizados
- Financial context completo
- Monthly plan del mes actual si existe

El agente recibe todo en el mensaje inicial. **No llama herramientas de datos.** Solo calcula y emite `emit_ui_event(show_plan_proposal)`.

### Fase 2 — Propuesta del agente (card en UI)

El agente presenta el plan ZBB completo. La card debe mostrar:
- Ingreso fijo planificado + nota sobre variable ("si entra Grupo 525, se destina 100% a snowball")
- Desglose de obligaciones por categoría (no un solo número)
- Cómo se distribuye el margen libre, categoría por categoría
- Alertas y oportunidades detectadas
- Botones: **Ajustar** | **Confirmar plan**

### Fase 3 — Confirmación y persistencia

Al confirmar:
1. `POST /api/v1/monthly_plans/confirm` → `MonthlyFinancialPlan(status: confirmed, confirmed_at: now)`
2. `PendingAction(budget_planning)` → `status: completed`
3. `CompletenessIndicator` elimina `monthly_plan` de los gaps

---

## 6. Arquitectura técnica

### 6.1 Migraciones pendientes

```ruby
# 1. budget_category en recurring_obligations
add_column :recurring_obligations, :budget_category, :string
add_index :recurring_obligations, [:account_id, :budget_category]
# Validación: inclusion in 9 system categories + custom

# 2. Relación polimórfica en pending_actions
add_column :pending_actions, :actionable_type, :string
add_column :pending_actions, :actionable_id, :bigint
add_index :pending_actions, [:actionable_type, :actionable_id]
# pending_action.actionable → MonthlyFinancialPlan

# 3. status 'provisional' en monthly_financial_plans
# Agregar al enum existente: draft | provisional | confirmed
```

### 6.2 Endpoint GET /api/v1/budget_context

Respuesta consolidada para el agente y el frontend:

```json
{
  "income": {
    "fixed_total": 6480000,
    "variable_projection": 2250000,
    "variable_note": "Grupo 525 ($3.000.000) al 75% de confiabilidad",
    "sources": [...]
  },
  "obligations": {
    "total": 4427149,
    "by_category": {
      "housing": { "total": 2500000, "items": [...] },
      "utilities": { "total": 230716, "items": [...] },
      ...
    }
  },
  "debt_minimums": {
    "total": 1696433,
    "debts": [...]
  },
  "financial_context": {
    "phase": "debt_payoff",
    "strategy": "snowball",
    "reward_pct": 5
  },
  "existing_plan": null,
  "gaps": {
    "missing_income": false,
    "missing_obligations": false,
    "obligations_seem_low": false
  }
}
```

### 6.3 Motor de cálculo BudgetCalculator (service en Rails)

```
base_income         = sum(income_sources WHERE classification = 'fixed')
variable_projection = sum(income × reliability_score/100) WHERE classification = 'variable'
recurring_total     = sum(recurring_obligations WHERE active = true)
debt_minimums       = sum(debts.monthly_payment WHERE status = 'active')
buffer              = según fase:
                        debt_payoff     → 0 (o mínimo definido por usuario)
                        emergency_fund  → 10-15% de base_income
                        investing       → definido por financial_context
snowball_extra      = free_margin × (1 - reward_pct/100)  # solo en debt_payoff
reward_allowance    = free_margin × (reward_pct/100)
free_margin         = base_income - recurring_total - debt_minimums - buffer
```

El cálculo ocurre en Rails antes de llamar al agente. El agente recibe los números, no los calcula — solo decide la distribución del `free_margin` dentro de las categorías discretionary.

---

## 7. Pendientes UI

### 7.1 La card de propuesta del agente no sigue el estilo de la aplicación

**Problema:** `AgentEventRenderer` usa una card flotante con estilos hardcodeados (`#1a1d23`, `rgba(231, 236, 244, 0.55)`, colores hex directos) en lugar de los design tokens (`var(--color-text-secondary)`, `var(--text-sm)`, etc.) y no sigue el patrón de modal establecido en la aplicación.

**Patrón establecido en la app:** Los wizards y modales usan `IonModal` de Ionic con `IonHeader` + `IonToolbar` + `IonTitle` + `IonButtons` + `IonContent`. El CSS interno usa únicamente CSS variables del sistema de diseño. Ver `IncomeSetupWizard` como referencia.

**Lo que hay que cambiar:**
- La `PlanProposalCard` debería abrirse como `IonModal` (con `breakpoints` para mobile bottom sheet, full en desktop) en lugar de una card flotante con `position: fixed`
- Reemplazar todos los colores hardcodeados por `var(--color-*)`, `var(--text-*)`, `var(--font-*)`
- El header del modal debe seguir el patrón: eyebrow label + título + botón de cierre en `IonButtons slot="end"`
- Las acciones (Descartar / Confirmar) deben usar el componente `Button` con las mismas variantes que el resto de la app (`ghost` y `primary`)
- En desktop: modal centrado con `max-width: 480px`
- En mobile: bottom sheet con `breakpoints={[0, 0.75, 1]}` igual que otros modales

**Referencia de implementación:** `IncomeSetupWizard.tsx` + `IncomeSetupWizard.module.css`

---

## 8. Lo que NO se construye en esta fase

- Envelope tracking en tiempo real (categoría vs gasto del mes) — futuro
- Budget rollover automático mes a mes — futuro
- Notificaciones cuando una categoría supera el límite — futuro
- Soporte para aguinaldo / bonos estacionales — futuro
- Comparativa mes a mes — futuro
