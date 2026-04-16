# Modulo Finanzas - Fases de Ejecucion

Este roadmap ya no describe un prototipo. Describe el sistema real despues de:

- migracion a API + Brain
- captura en tiempo real por Telegram
- UI/PWA operativa
- categorias conductuales, deudas, budgets, income_sources y recurring_obligations

La regla nueva es esta:

- no se reabre lo que ya esta operativo
- la deuda conceptual de presupuesto se mueve a una fase propia
- el sistema deja de mezclar `budget`, `projected transactions` e `income assumptions`

---

## Fase 1 - Core: Transacciones y Categorias

**Estado**: `completada`

**Resultado alcanzado**

- transacciones persistidas en PostgreSQL
- categorias y subcategorias del sistema
- CRUD completo de transacciones
- clasificacion por categoria/subcategoria
- soporte de `confirmed`, `pending`, `projected`
- deduplicacion tecnica por `source_event_id`
- agente en tiempo real registrando y corrigiendo movimientos
- UI operativa para revisar, editar y eliminar transacciones

**Criterio de cierre**

La capa transaccional ya reemplaza el Excel como fuente de verdad. Cualquier trabajo nuevo debe asumir que esta fase esta cerrada y no reabrirla salvo por bugs puntuales.

---

## Fase 2 - Brain y Operacion Conversacional

**Estado**: `completada`

**Resultado alcanzado**

- `daniel15k-agents` desplegado en Railway
- webhook de Telegram operando en el Brain
- agente nocturno migrado al Brain
- scheduler reemplazando GitHub Actions para ejecuciones recurrentes
- autenticacion por `service_account` y `delegation`
- chat en tiempo real con herramientas de lectura/escritura sobre la API
- wizard conversacional inicial para contexto y presupuesto

**Nota importante**

La infraestructura del Brain esta cerrada. Lo que queda pendiente ya no es "tener Brain", sino **corregir el modelo de planeacion mensual**. Esa deuda se mueve explicitamente a la Fase 3.

---

## Fase 3 - Planeacion Mensual y Completitud Contextual

**Estado**: `prioridad maxima`

**Tesis**

El sistema ya sabe registrar movimientos, pero todavia no sabe convertir ingresos estructurales en un plan mensual confiable. Hoy existe `budgets`, existen `income_sources`, y existen `projected transactions`; lo que falta es la capa que decide:

- con que ingreso vivir este mes
- que parte del ingreso es base vs variable
- que hacer cuando entra dinero extra
- que gaps bloquean una recomendacion seria

### Problema que resuelve

Corregir la confusion entre:

- `transactions.status = projected`
- `budgets`
- `income_sources`
- `financial_context`

La planeacion mensual deja de depender de campos legacy como `monthly_income_1/2` y pasa a vivir en una entidad propia.

### Que se construye

#### 1. Nueva entidad `monthly_financial_plans`

```sql
id, user_id, account_id,
month, year,
status,                          -- draft | confirmed | superseded
mode,                            -- conservative | expected
base_budget_income,              -- piso confiable del mes
expected_variable_income,        -- componente variable esperado, no comprometido
recurring_obligations_total,
debt_minimums_total,
protected_buffer_amount,
discretionary_limit,
overflow_rule,                   -- debt | emergency_fund | investment | mixed
overflow_rule_detail (jsonb),
reward_pct,
investment_target,
debt_strategy,
assumptions (jsonb),
confirmed_at,
created_at, updated_at
```

#### 2. Evolucion de `income_sources`

`income_sources` deja de ser solo una agenda de entradas esperadas y pasa a soportar planeacion:

```sql
classification,                  -- base | variable | seasonal | one_time
cadence,                         -- monthly | biweekly | irregular
reliability_score,               -- 0..100
last_confirmed_at,
evidence_source
```

`is_variable` puede mantenerse de forma transitoria, pero deja de ser la unica senal semantica.

#### 3. Completeness state minimo

Proyeccion o tabla cacheada con estado por dimension:

- `income_profile`
- `debts`
- `recurring_expenses`
- `strategy`
- `monthly_plan`

Estados minimos:

- `missing`
- `partial`
- `sufficient`
- `stale`
- `conflicting`

#### 4. Preflight del agente

Antes de responder a intents como:

- "hazme el presupuesto"
- "como voy este mes"
- "que hago con este ingreso extra"

el agente debe evaluar si faltan datos criticos. El resultado puede ser:

- flujo normal
- wizard bloqueante
- soft nudge

#### 5. Wizard de plan mensual reescrito

El wizard deja de preguntar por quincenas hardcodeadas y pasa a confirmar:

- ingreso base confiable
- ingresos variables esperados
- obligaciones estructurales
- deuda minima total
- limite discrecional
- regla de overflow
- recompensa opcional

### Contrato nuevo

#### `budget`

Sigue siendo un limite por categoria. No desaparece.

#### `projected transaction`

Sigue representando un evento esperado concreto de cashflow. No desaparece.

#### `monthly_financial_plan`

Se vuelve el contrato operativo del mes. Es la capa que hoy falta.

### Endpoints nuevos o ajustados

```text
GET  /api/v1/monthly_plans/current
GET  /api/v1/monthly_plans?month=&year=
POST /api/v1/monthly_plans/generate
POST /api/v1/monthly_plans/:id/confirm
PATCH /api/v1/monthly_plans/:id

GET  /api/v1/completeness
POST /api/v1/context/detect_missing
POST /api/v1/agents/preflight
```

### Criterios de aceptacion

- [ ] existe `monthly_financial_plans` y puede confirmarse uno por mes
- [ ] el sistema soporta distinguir ingreso `base` de ingreso `variable`
- [ ] el wizard deja de depender de `monthly_income_1/2`, `income_day_1/2` y `monthly_rent`
- [ ] `summary` deja de calcular el contexto financiero desde campos legacy
- [ ] `base_budget_income` se calcula desde `income_sources` segun `classification` y `mode`
- [ ] el usuario puede presupuestar sobre `6.4M` y tratar `2.9M` como overflow
- [ ] cuando entra ingreso extra, el sistema aplica `overflow_rule` sin inflar el presupuesto base
- [ ] el agente hace `preflight` y decide entre flujo normal, wizard o soft nudge
- [ ] existe estado minimo de completitud para `income_profile`, `debts`, `recurring_expenses`, `strategy` y `monthly_plan`
- [ ] tests cubren al menos:
  - plan conservador
  - plan expected
  - ingreso base + ingreso variable
  - falta de `monthly_plan`
  - overflow rule aplicada correctamente

---

## Fase 4 - Deudas y Metas Guiadas por el Plan

**Estado**: `parcial`

**Objetivo**

Construir las decisiones de deuda y ahorro encima del `monthly_financial_plan`, no al margen de el.

### Que se construye

- completar `savings_goals`
- calculo de aporte mensual requerido
- integracion de `overflow_rule` con deuda, ahorro e inversion
- sugerencias de aceleracion de deuda basadas en excedente real del plan

### Criterios de aceptacion

- [ ] `POST /api/v1/savings_goals` calcula `monthly_contribution_needed`
- [ ] el summary incluye `savings_goals`
- [ ] si el plan del mes define overflow a deuda, el summary lo refleja
- [ ] si el plan del mes define overflow a ahorro, el summary lo refleja
- [ ] el agente nocturno menciona desalineaciones entre plan mensual y ejecucion real

---

## Fase 5 - Motor Conductual

**Estado**: `pendiente`

**Objetivo**

Convertir categorias, plan mensual y contexto en intervenciones consistentes.

### Que se construye

- `behavior_profile` editable y basado en evidencia, no etiquetas moralistas
- `behavior_snapshot` derivado
- `behavior_interventions`
- `behavior_feedback_loops`
- triggers tipo:
  - discretionary alto antes de fecha critica
  - ingreso extra sin regla aplicada
  - plan mensual desalineado
  - riesgo en payday

### Criterios de aceptacion

- [ ] el sistema diferencia entre gap informacional, de politica y conductual
- [ ] el agente puede aplicar nudges, friccion o refuerzo segun contexto
- [ ] existe trazabilidad de trigger -> intervencion -> respuesta -> resultado

---

## Fase 6 - Analytics y Dashboard

**Estado**: `pendiente`

**Objetivo**

Dar visibilidad de tendencia, adherencia al plan y patron conductual sin convertir todas las pantallas en dashboards densos.

### Que se construye

- analytics de trend mensual
- breakdown por categoria
- adherencia al `discretionary_limit`
- uso de `overflow_rule`
- deuda vs plan
- comparativas de estabilidad mensual

### Criterios de aceptacion

- [ ] `monthly_plan` aparece como eje del dashboard
- [ ] analytics muestran adherencia al plan, no solo gasto bruto
- [ ] el usuario puede distinguir:
  - gasto real
  - gasto proyectado
  - presupuesto
  - overflow usado

---

## Definicion de done global del modulo

El modulo Finanzas se considera realmente completo cuando:

- [x] Fase 1 esta cerrada
- [x] Fase 2 esta cerrada en infraestructura y operacion conversacional
- [ ] Fase 3 elimina por completo la dependencia de ingresos legacy en planeacion
- [ ] existe `monthly_financial_plan` como contrato operativo del mes
- [ ] el presupuesto base puede construirse sin depender de ingresos variables
- [ ] el agente usa completitud contextual antes de abrir wizard o recomendar acciones
- [ ] el summary distingue con claridad entre:
  - base budget income
  - projected cashflow
  - budget limits
  - overflow handling
- [ ] deudas, ahorro y coaching ya consumen el plan mensual
