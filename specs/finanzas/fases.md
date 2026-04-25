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
- soporte de `confirmed` y `pending`
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

**Estado**: `en progreso — núcleo completo, integración pendiente`

**Subfase activa**: [Fase 3.4 — Living Budget Integration](./phase-3-4-living-budget-integration.md)

**Tesis**

El sistema ya sabe registrar movimientos, pero todavia no sabe convertir ingresos estructurales en un plan mensual confiable. Hoy existe `budgets` e `income_sources`; lo que falta es la capa que decide:

- con que ingreso vivir este mes
- que parte del ingreso es base vs variable
- que hacer cuando entra dinero extra
- que gaps bloquean una recomendacion seria

### Problema que resuelve

Corregir la confusion entre:

- `budgets`
- `income_sources`
- `financial_context`

La planeacion mensual deja de depender de campos legacy como `monthly_income_1/2` y pasa a vivir en una entidad propia.

### Completado dentro de Fase 3 (2026-04-24)

- ✅ `monthly_financial_plans` como entidad operativa del mes
- ✅ `income_sources` con classification / cadence / reliability_score
- ✅ Completeness state (5 dimensiones) — `/api/v1/completeness`
- ✅ Preflight del agente — `/api/v1/agents/preflight`
- ✅ Wizard de plan mensual con propuesta calculada (no formulario vacío)
- ✅ `LiquidityProjection` interactor — `safe_to_deploy` como guardrail universal
- ✅ Fix `pending_income` para ingresos variables sin confirmar
- ✅ Fix `burn_rate` aggregation (agrupación por categoría, no subcategoría)
- ✅ `safe_to_deploy` como techo de `recommended_action` — nunca recomienda más de lo disponible
- ✅ `AgentInsights` — generación diaria con drift checker, Haiku validity gate, Sonnet structured output
- ✅ Dashboard reestructurado (3 zonas: Hero + Snapshot + Detalle) con recharts
- ✅ UI consume `agent_insights` en el Hero con fallback y botón on-demand

### Pendiente dentro de Fase 3

- ⬜ **Historial de planes y ejecución mensual** (ver [plan-history-and-execution.md](./plan-history-and-execution.md))
  - Migración: `income_actual`, `expense_actual`, `execution_snapshot`, `closed_at`
  - `CloseMonthlyPlan` interactor — calcula actuals vs plan, idempotente
  - `GET /monthly_plans` como historial paginado real
  - `POST /monthly_plans/:id/close` — cierre de mes
  - `ProposeBudget` usa últimos 3 planes cerrados para detectar patrones
- ⬜ Plan rolling — heredar plan anterior como borrador en el mes siguiente
- ⬜ `savings_goals` con `monthly_contribution_needed` conectados al plan
- ⬜ Matching estructural transacción → deuda / planned_expense / recurrente
- ⬜ Reglas cruzadas deuda ↔ recurrente hardened
- ⬜ Wizard: líneas bloqueadas cuando vienen de fuente de verdad estructural
- ⬜ Medios de pago y modelo de tarjeta de crédito (ver [payment-sources-credit-card.md](./payment-sources-credit-card.md))

El detalle funcional y los criterios de cierre de ese bloque viven en:

- [phase-3-4-living-budget-integration.md](./phase-3-4-living-budget-integration.md)

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

---

#### 6. Agente web bidireccional — canal completo

El web app tiene su propio canal con el agente, independiente de Telegram. El agente es el mismo cerebro; lo que cambia es el canal de entrada y las herramientas de salida que usa.

##### Principio de diseno

El wizard de presupuesto no es un formulario — es una conversacion guiada por el agente renderizada como componentes estructurados. El usuario no habla con texto: interactua con tarjetas, formularios y propuestas que el agente genera dinamicamente.

Telegram y web son canales separados que convergen en el mismo agente:

```
Telegram  →  webhook        →  agente  →  send_telegram (texto + inline_keyboard)
Web       →  /agents/chat   →  agente  →  emit_ui_event (componentes estructurados)
```

##### Canal de salida: herramientas del agente para web

El agente dispone de cinco herramientas de salida especificas para el canal web:

| tool | proposito | componente en front |
|---|---|---|
| `emit_ui_event: show_plan_proposal` | proponer draft calculado del plan mensual | `PlanProposalCard` |
| `emit_ui_event: show_card` | informacion, advertencia o exito | `AgentCard` |
| `emit_ui_event: show_form` | formulario dinamico con campos y valores pre-llenados | `DynamicForm` |
| `emit_ui_event: request_confirmation` | solicitar confirmacion explicita antes de guardar | `ConfirmCard` |
| `navigate_to(route)` | redirigir al usuario a una pagina al terminar un flujo | navegacion del router |

El agente nunca usa `send_telegram` cuando el `source` es `"web"`. El contexto del canal llega en cada request.

##### Canal de entrada: web → agente

El front-end se comunica con el agente via un unico endpoint:

```
POST /api/v1/agents/chat
{
  "message": "string | null",       // texto libre del usuario
  "event_response": {               // respuesta estructurada a un evento previo
    "event_id": 123,
    "type": "form_submitted | confirmed | dismissed",
    "data": {}
  },
  "session_id": "string",
  "source": "web"
}
```

El agente recibe el mensaje, corre con las mismas herramientas de lectura/escritura que en Telegram, y responde emitiendo eventos web en lugar de mensajes de Telegram. La conversacion se almacena por `session_id`.

##### Flujo completo del wizard de presupuesto

```
1. Usuario toca "Comenzar presupuesto"
   → POST /agents/chat { message: "Quiero crear mi plan mensual", source: "web" }

2. Agente detecta datos disponibles, calcula draft
   → emit_ui_event: show_plan_proposal { draft, warnings }
   → Front renderiza PlanProposalCard

3. Usuario ajusta una linea (ej. baja obligaciones)
   → POST /agents/chat { event_response: { type: "form_submitted", data: { ... } } }
   → Agente valida, recalcula
   → emit_ui_event: show_card { tone: "warning", ... }  si hay conflicto
   → emit_ui_event: show_plan_proposal actualizado  si es valido

4. Usuario confirma
   → POST /agents/chat { event_response: { type: "confirmed", event_id: ... } }
   → Agente guarda monthly_financial_plan
   → emit_ui_event: show_card { tone: "success", title: "Plan confirmado" }
   → navigate_to("/budgets")
```

##### Plan rolling: confirmacion mensual, no re-creacion

El plan no se crea desde cero cada mes. El agente:

1. Detecta si existe plan confirmado para el mes actual
2. Si no existe, hereda el del mes anterior como draft
3. Marca que cambio respecto al mes anterior (ingreso variable no confirmado, nueva deuda, etc.)
4. Emite `show_plan_proposal` con las diferencias resaltadas — el usuario confirma o ajusta
5. Si ya existe plan confirmado, el agente puede proponer ajustes puntuales sin reabrir todo

Esto convierte el presupuesto en algo que se mantiene vivo sin friccion, no en un formulario que hay que rellenar cada mes.

##### Contexto de ciudad en el system prompt

El agente conoce rangos de costo de vida colombiano para que sus sugerencias sean realistas:

- Almuerzo corriente: $12.000–$25.000 (Pasto mas bajo, Bogota mas alto)
- Transporte urbano: $3.000–$6.000 por trayecto segun ciudad
- Salida / ocio: $80.000–$200.000 segun ciudad y tipo de plan
- Mercado mensual (1 persona): $300.000–$600.000 segun ciudad y habitos

Si no conoce la ciudad del usuario, la pregunta antes de proponer cifras.

##### Que se construye

**API (Rails)** — ya construido:
```text
POST  /api/v1/agent_events           -- agente escribe evento (emit_ui_event)
GET   /api/v1/agent_events/pending   -- front hace polling
PATCH /api/v1/agent_events/:id/consume
```

**API (Rails)** — por construir:
```text
POST  /api/v1/agents/chat            -- entrada web → agente
```

**Agente (Python)** — ya construido:
- Tool `emit_ui_event(type, payload)`

**Agente (Python)** — por construir:
- Tool `navigate_to(route)` — escribe evento tipo `navigate` con la ruta destino
- Handler de `POST /agents/chat`: detecta `source: web`, corre el agente, usa tools web
- Logica de plan rolling: hereda mes anterior, marca diferencias, propone confirmacion

**Front-end (Ionic React)** — ya construido:
- Hook `useAgentEvents` (polling)
- `AgentEventRenderer` con registry de componentes
- `PlanProposalCard`, `AgentCard`, `ConfirmCard`

**Front-end (Ionic React)** — por construir:
- Hook `useWebChat(sessionId)` — wrappea `POST /agents/chat` para enviar mensajes y respuestas de eventos
- Manejo de evento `navigate` en `useAgentEvents` — ejecuta navegacion del router
- Conectar boton "Comenzar presupuesto" al `useWebChat` en lugar de abrir wizard estatico

##### Criterios de aceptacion

- [ ] `POST /api/v1/agents/chat` recibe mensaje web y corre el agente en modo web
- [ ] el agente usa `emit_ui_event` (no `send_telegram`) cuando `source == "web"`
- [ ] el wizard de presupuesto arranca con propuesta calculada, no formulario vacio
- [ ] el usuario puede ajustar el draft y el agente revalida en la misma sesion
- [ ] confirmar el plan desde el web guarda `monthly_financial_plan` y navega a `/budgets`
- [ ] el plan del mes se hereda del anterior; el agente marca las diferencias
- [ ] si el agente no conoce la ciudad del usuario, la pregunta antes de proponer cifras
- [ ] el agente nocturno puede emitir propuestas web Y mensajes de Telegram en paralelo

---

### Contrato nuevo

#### `budget`

Sigue siendo un limite por categoria. No desaparece.

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
- [ ] el canal de eventos agente → front-end esta operativo (tabla `agent_ui_events`, polling, registry)
- [ ] el wizard de presupuesto arranca con propuesta calculada por el agente, no con campos vacios
- [ ] el agente conoce rangos de costo de vida por ciudad colombiana y los usa en la propuesta
- [ ] tests cubren al menos:
  - plan conservador
  - plan expected
  - ingreso base + ingreso variable
  - falta de `monthly_plan`
  - overflow rule aplicada correctamente

---

## Fase 3.5 - Medios de Pago y Tarjetas de Crédito

**Estado**: `spec definido — pendiente de implementar`

**Objetivo**

Resolver la duplicación de gastos con tarjeta de crédito. Hoy el sistema registra las compras individuales y también el pago mensual al banco como un segundo gasto. Esta fase introduce el campo `payment_source` en transactions y el concepto de `credit_card_status: pending | settled` para manejar el ciclo completo de compra → pago sin duplicar.

**Spec completo:** [payment-sources-credit-card.md](./payment-sources-credit-card.md)

### Qué se construye

- Migración: `payment_source` y `credit_card_status` en `transactions`
- UI: botones de medio de pago en el registro de transacción
- Chat agent: extracción de medio de pago en el flujo de registro
- Agente nocturno: distinción entre email de compra y email de abono
- Flujo de liquidación FIFO al recibir un pago
- `LiquidityProjection`: crédito pendiente como obligación futura
- Dashboard: sección de crédito pendiente en Zona 3

### Criterios de aceptación

- [x] una compra con `payment_source: credit_card` no cuenta dos veces cuando llega el abono
- [x] el agente nocturno no crea gasto nuevo al capturar un email de pago a tarjeta
- [x] el pool de crédito pendiente refleja el total real de compras no saldadas
- [x] el flujo de liquidación marca transacciones como `settled` en orden FIFO
- [x] el `safe_to_deploy` considera el crédito pendiente como obligación si el corte cae en el próximo ciclo

---

## Fase 4 - Deudas, Metas y Gamificación Guiadas por el Plan

**Estado**: `parcial`

**Objetivo**

Construir las decisiones de deuda y ahorro encima del `monthly_financial_plan`, no al margen de el.

### Que se construye

- completar `savings_goals`
- calculo de aporte mensual requerido
- integracion de `overflow_rule` con deuda, ahorro e inversion
- sugerencias de aceleracion de deuda basadas en excedente real del plan

### Que se construye (actualizado 2026-04-24)

- `savings_goals` con `monthly_contribution_needed` calculado
- Sistema de milestones y setbacks contextual al plan (ver [gamification.md](./gamification.md))
- Chat agent: flujo completo para "deuda liquidada" — marca paid_off, desactiva recurrente, crea milestone
- Nightly agent: detección automática de milestones desde comparación de snapshots
- Integración de milestones en `agent_insights.signals`
- UI: badge del último logro en Hero del Dashboard

### Criterios de aceptacion

- [ ] `POST /api/v1/savings_goals` calcula `monthly_contribution_needed`
- [ ] el summary incluye `savings_goals`
- [ ] si el plan del mes define overflow a deuda, el summary lo refleja
- [ ] si el plan del mes define overflow a ahorro, el summary lo refleja
- [ ] el agente nocturno menciona desalineaciones entre plan mensual y ejecucion real
- [ ] existe tabla `user_milestones` con hitos únicos y recurrentes
- [ ] el chat agent detecta "liquidé una deuda" y ejecuta el flujo completo (paid_off + recurrente + milestone)
- [ ] los milestones aparecen como signals en el insight diario
- [ ] el agente presenta setbacks como información, nunca como reproche

---

## Fase 5 - Motor Conductual

**Estado**: `pendiente futuro — no iniciar hasta cerrar Fases 3 y 4`

**Referencia**: `specs/deep-research-report.md` define el modelo completo.

**Objetivo**

Convertir el historial transaccional, el plan mensual y el contexto financiero en un perfil conductual inferido que permita intervenciones personalizadas, no genericas.

### Principios de diseno

- El `behavior_profile` es inferido desde evidencia, no declarado por el usuario ni usado como etiqueta moral.
- Las intervenciones siguen el framework COM-B: identificar si el gap es de capacidad, oportunidad o motivacion antes de decidir el tipo de nudge.
- La motivacion autonoma (el usuario quiere) se trata diferente a la controlada (el usuario siente presion); los nudges deben apuntar a reforzar la autonoma.
- Trazabilidad obligatoria: `trigger → intervencion → respuesta → resultado`.

### Que se construye

#### `behavior_profile`

Perfil inferido con seis ejes (segun deep-research-report):

- `money_management_domains` — donde el usuario tiene control vs. donde falla sistematicamente
- `motivation_quality` — autonoma vs. controlada; determina que tipo de intervencion tiene sentido
- `self_efficacy_and_control` — percepcion del usuario sobre su capacidad de cambio
- `monitoring_habit` — frecuencia y profundidad de revision del sistema
- `credit_reliance` — patron de uso de deuda como herramienta vs. como salida
- `stress_and_shame_risk` — indicadores de que el dinero genera evitacion en lugar de accion

#### `behavior_snapshot`

Estado derivado del perfil mas el contexto del mes actual. No es editable; se recalcula.

#### `behavior_interventions`

Mapa de triggers con tipo de intervencion recomendada:

| trigger | gap type | intervencion |
|---|---|---|
| discretionary alto antes de fecha critica | conductual | friccion util |
| ingreso extra sin regla aplicada | de politica | if-then sugerido |
| plan mensual desalineado | informacional | reporte de brecha |
| patron de evasion (no abre el sistema en dias de tension) | conductual | re-engagement suave |

#### `behavior_feedback_loops`

Cierre del ciclo: el sistema registra si la intervencion fue aceptada, ignorada o revertida, y ajusta la confianza del perfil.

### Criterios de aceptacion

- [ ] `behavior_profile` existe como entidad persistida con los seis ejes
- [ ] el perfil se actualiza desde evidencia transaccional, no desde input manual
- [ ] el sistema clasifica cada gap como informacional, de politica o conductual antes de intervenir
- [ ] existe al menos un flujo de if-then planning implementado (ingreso extra → regla aplicada)
- [ ] el agente diferencia nudges para motivacion autonoma vs. controlada
- [ ] existe trazabilidad de `trigger → intervencion → respuesta → resultado`
- [ ] ningun eje del perfil se muestra al usuario como etiqueta; solo se usa para personalizar el agente

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
- [x] `monthly_financial_plan` existe como contrato operativo del mes
- [x] el agente usa completitud contextual antes de abrir wizard o recomendar acciones
- [x] el summary distingue con claridad entre base budget income, projected cashflow, budget limits y overflow handling
- [x] `safe_to_deploy` es el guardrail universal — ninguna recomendacion supera lo disponible
- [x] el agente genera insights diarios con drift checker y Sonnet estructurado
- [ ] Fase 3 elimina por completo la dependencia de ingresos legacy en planeacion (plan rolling pendiente)
- [ ] el presupuesto base puede construirse sin depender de ingresos variables
- [ ] `savings_goals` conectados al plan con aporte mensual calculado
- [ ] deudas, ahorro y gamificacion consumen el plan mensual como fuente de verdad
- [ ] milestones y setbacks registrados y accesibles para el agente
- [ ] el agente puede narrar progreso contextual: "2/5 deudas liquidadas, ritmo actual: 8 meses para el objetivo"
