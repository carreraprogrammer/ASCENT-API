# Módulo Finanzas — Fases de Ejecución

Cada fase es desplegable y funcional de forma independiente. No se avanza a la siguiente hasta que todos los criterios de aceptación de la actual estén verificados.

---

## Fase 1 — Core: Transacciones y Categorías

**Objetivo**: El agente puede reemplazar el Excel. Registra gastos, los clasifica, y resuelve pendientes.

**Duración estimada**: 1 semana

### Qué se construye

- Migración a PostgreSQL (reemplaza MySQL del boilerplate)
- Migrations: `categories`, `subcategories`, `transactions`
- Seeds: categorías base del sistema (no borrables) + subcategorías iniciales
- Dominio `finanzas`: entities, repositories, interactors, presenters
- Endpoints:
  - `GET /api/v1/categories`
  - `POST /api/v1/categories`
  - `GET /api/v1/transactions?month=&year=`
  - `GET /api/v1/transactions/pending`
  - `POST /api/v1/transactions`
  - `PATCH /api/v1/transactions/:id`
  - `DELETE /api/v1/transactions/:id`
- Migración de datos: script Python que lee el Excel actual y hace POST a la API
- Deploy en Railway

### Criterios de aceptación

- [ ] `POST /api/v1/transactions` con todos los campos válidos retorna `201` y el objeto creado en JSON:API
- [ ] `POST /api/v1/transactions` con `amount` negativo retorna `422` con error descriptivo
- [ ] `GET /api/v1/transactions?month=04&year=2026` retorna solo las transacciones de abril 2026
- [ ] `GET /api/v1/transactions/pending` retorna solo transacciones con `status: "pending"`
- [ ] `PATCH /api/v1/transactions/:id` actualiza `status`, `category_id`, `subcategory_id`
- [ ] `POST /api/v1/categories` crea una categoría nueva; el agente puede llamarlo
- [ ] Las categorías con `is_system: true` no pueden borrarse (retorna `403`)
- [ ] Las 7 categorías base y sus subcategorías existen en BD tras `rails db:seed`
- [ ] El script de migración del Excel importa todas las transacciones de abril 2026 sin errores
- [ ] El agente nocturno en GitHub Actions usa la API en lugar de Dropbox/openpyxl
- [ ] `bundle exec rspec` pasa al 100% para el dominio finanzas
- [ ] `docker compose up` + `rails db:migrate` levanta sin errores en Railway

---

## Fase 2 — Brain Layer + Presupuestos Inteligentes

**Objetivo**: Introducir el Brain (FastAPI) como capa de inteligencia entre Telegram y la API. El usuario puede planificar su presupuesto de forma interactiva cada quincena, recibir un plan de flujo de caja con recomendaciones basadas en ciencia del comportamiento, y el agente nocturno alerta antes de que se pase del presupuesto — no después.

**Duración estimada**: 1 semana

---

### Arquitectura que se establece en esta fase

```
Telegram
    ↕
FastAPI — daniel15k-agents  (Brain)
    ├── webhook/telegram      ← se mueve desde Rails
    ├── agents/nightly        ← revision_nocturna.py
    ├── agents/planning       ← planificacion_quincenal.py
    └── scheduler             ← reemplaza GitHub Actions + Railway cron
    ↕
Rails API — daniel15k-api   (Data)
    ├── /transactions
    ├── /budgets              ← nuevo
    ├── /debts                ← nuevo (adelantado desde Fase 3)
    ├── /financial_context    ← nuevo (adelantado desde Fase 4)
    ├── /pending_actions      ← nuevo
    └── /summary              ← nuevo
```

**Principio:** Rails no sabe nada de Claude ni de Telegram. El Brain orquesta, Rails persiste.

---

### Parte 1 — Rails API: nuevas tablas y endpoints

#### Migrations

**`budgets`**
```sql
id, user_id, category_id,
month, year,
amount_limit (integer),        -- en pesos COP
created_at, updated_at
UNIQUE (user_id, category_id, month, year)
```

**`debts`**
```sql
id, user_id,
name, debt_type,               -- credit_card | personal_loan | family | mortgage
original_amount, current_balance, monthly_payment,
interest_rate (decimal),       -- % mensual
status,                        -- active | paid_off | paused
payoff_date (date),
created_at, updated_at
```

**`financial_contexts`**
```sql
id, user_id,
phase,                         -- debt_payoff | emergency_fund | investing | wealth_building
strategy,                      -- snowball | avalanche (solo en debt_payoff)
monthly_income_1 (integer),    -- 1a quincena (ej: EMAPTA)
monthly_income_2 (integer),    -- 2a quincena (ej: 525)
income_day_1 (integer),        -- día del mes en que cae (ej: 4)
income_day_2 (integer),        -- día del mes en que cae (ej: 19)
reward_pct (integer),          -- % del excedente que va a recompensa (default: 5)
notes (text),
updated_at
```

**`pending_actions`**
```sql
id, user_id,
action_type,                   -- budget_planning | debt_setup | onboarding | ...
current_step (integer),
total_steps (integer),
context (jsonb),               -- datos acumulados entre pasos
status,                        -- waiting_response | in_progress | completed | cancelled | expired
expires_at (datetime),
created_at, updated_at
```

#### Nuevos endpoints Rails

```
GET  /api/v1/budgets?month=&year=
POST /api/v1/budgets              (bulk: acepta array)
PATCH /api/v1/budgets/:id

GET  /api/v1/debts
POST /api/v1/debts
PATCH /api/v1/debts/:id

GET  /api/v1/financial_context
PATCH /api/v1/financial_context

GET  /api/v1/pending_actions/active   ← el Brain consulta si hay flujo abierto
POST /api/v1/pending_actions
PATCH /api/v1/pending_actions/:id

GET  /api/v1/summary?month=&year=
```

#### `GET /api/v1/summary` — respuesta completa

```json
{
  "period": { "month": 5, "year": 2026 },
  "balance": {
    "income_confirmed": 6414526,
    "income_projected": 6100000,
    "expense_confirmed": 3200000,
    "expense_pending": 86000,
    "expense_projected": 893000,
    "balance_confirmed": 3214526,
    "balance_total": 8835526
  },
  "burn_rate": {
    "days_elapsed": 13,
    "days_in_month": 31,
    "categories": [
      {
        "category": "Discrecional",
        "budget": 500000,
        "spent": 320000,
        "projected": 762000,
        "pct": 152,
        "on_track": false,
        "alert": "⚠️ Discrecional: vas a $762.000 proyectados vs presupuesto de $500.000"
      }
    ]
  },
  "debts": {
    "total_balance": 8500000,
    "monthly_payments": 1144000,
    "recommended_payment": { "name": "CrediExpress #238105", "balance": 830000, "strategy": "snowball" }
  },
  "financial_context": {
    "phase": "debt_payoff",
    "strategy": "snowball",
    "monthly_surplus_estimate": 800000,
    "recommended_action": "Abona $760.000 al CrediExpress #238105 — lo liquidas en 1 mes."
  }
}
```

#### Limpieza en Rails
- Eliminar `TelegramController` (se mueve al Brain)
- Eliminar `TelegramUpdate` model y migration (el Brain maneja el estado)
- Eliminar rutas `/telegram/*`

---

### Parte 2 — FastAPI Brain (repositorio `daniel15k-agents`)

#### Estructura del repositorio

```
daniel15k-agents/
├── main.py                    ← FastAPI app
├── routers/
│   ├── webhook.py             ← POST /webhook/telegram
│   └── agents.py             ← POST /agents/nightly, /agents/planning
├── agents/
│   ├── nightly.py             ← revision_nocturna (migrado)
│   └── planning.py            ← agente de planificación quincenal
├── flows/
│   └── budget_wizard.py       ← máquina de estados del wizard
├── services/
│   ├── api_client.py          ← cliente HTTP para Rails API
│   └── telegram.py            ← enviar mensajes, botones, polls
├── scheduler.py               ← APScheduler: reemplaza GitHub Actions
├── requirements.txt
├── Dockerfile
└── railway.toml
```

#### Webhook (`POST /webhook/telegram`)

Lógica de entrada:

```
recibe update de Telegram
  → ¿hay PendingAction activo para este usuario?
      sí → delegar a flows/budget_wizard.py con el mensaje/callback
      no → flujo normal (registrar gasto, resolver callback de categorización)
```

#### Scheduler (reemplaza GitHub Actions)

```python
# APScheduler corriendo dentro del mismo proceso FastAPI
scheduler.add_job(run_nightly,   cron, hour=4,  minute=0)   # 11pm Colombia
scheduler.add_job(run_planning,  cron, day=1,   hour=13)    # 8am Colombia día 1
scheduler.add_job(run_planning,  cron, day=15,  hour=13)    # 8am Colombia día 15
```

---

### Parte 3 — Flujo de planificación quincenal

#### Escenarios cubiertos

| Escenario | Comportamiento |
|-----------|---------------|
| Sin financial_context ni deudas | Wizard completo: onboarding + planificación |
| Con contexto pero sin presupuestos del mes | Propuesta automática basada en historial |
| Con presupuestos del mes anterior | Propuesta con ajustes basados en desviaciones reales |
| Usuario responde "No" | No crea PendingAction. Silencio hasta próxima quincena |
| Usuario responde "Mañana" | Crea PendingAction expirado en 24h, reintenta al día siguiente |
| Usuario no responde en 48h | PendingAction expira, se cancela automáticamente |
| Usuario quiere ajustar una categoría | Vuelve al paso de esa categoría con el valor actual como default |
| Usuario aprueba todo | Escribe budgets vía Rails API, confirma con resumen |

#### Pasos del wizard `budget_planning`

```
Step 0 — Trigger
  Bot: "Hola Daniel 👋 Es quincena — ¿planificamos el presupuesto de mayo?"
  Botones: [Sí, vamos | No por ahora | Mañana]
  → "Sí" → crea PendingAction { step: 1 }
  → "No" → no hace nada
  → "Mañana" → crea PendingAction { expires_at: +24h, step: 0 }

Step 1 — Confirmar ingresos
  Bot: "Este mes esperas:
        • EMAPTA el día 4: $3.335.000
        • 525 el día 19: ~$3.000.000
        ¿Es correcto o cambió algo?"
  Botones: [Correcto ✓ | Cambió algo]
  → Correcto → step 2
  → Cambió → pregunta qué cambió (texto libre), actualiza financial_context, step 2

Step 2 — Comprometido (no negociable)
  Bot: "Tus gastos fijos este mes:
        • Arriendo: $2.500.000
        • CrediExpress #290742: $866.000
        • CrediExpress #238105: $83.000
        • Moto: $245.000
        • iPhone papá: $178.000
        Total comprometido: $3.872.000
        Estos salen de tu primera quincena (día 4). ¿Ok?"
  Botones: [Ok ✓ | Hay un cambio]
  → Ok → step 3
  → Cambio → recibe texto, actualiza deuda/gasto, recalcula, muestra de nuevo

Step 3 — Deuda recomendada (snowball)
  Bot: "Con la estrategia snowball, te recomiendo abonar $200.000 extra al
        CrediExpress #238105 (saldo $630.000). Lo liquidas en 3 meses.
        ¿Lo incluimos en el plan?"
  Botones: [Sí, incluirlo | Ajustar monto | No este mes]
  → Sí → guarda en context, step 4
  → Ajustar → pide monto, actualiza, step 4
  → No → anota en context, step 4

Step 4 — Necesario
  Bot: "Para lo necesario (mercado, transporte, celular, salud) el mes pasado
        gastaste $687.000. Te propongo presupuestar $700.000.
        ¿Te parece bien?"
  Botones: [Bien ✓ | Ajustar]
  → Bien → guarda, step 5
  → Ajustar → recibe monto, step 5

Step 5 — Discrecional
  Bot: "Discrecional (restaurantes, ocio, suscripciones, ropa):
        Abril gastaste $1.180.000 — estuvo alto.
        Teniendo en cuenta tus metas, te propongo $600.000.
        ¿Qué te parece?"
  Botones: [Perfecto | Necesito más | Puedo menos]
  → Perfecto → guarda, step 6
  → Necesito más / Puedo menos → recibe monto o ajuste porcentual, step 6

Step 6 — Recompensa
  Bot: "Si llegas al final del mes dentro del presupuesto, el 5% del excedente
        es tuyo para gastar sin culpa. Con este plan serían ~$85.000.
        ¿Ajustamos el porcentaje?"
  Botones: [Está bien | Cambiar %]
  → Está bien → guarda, step 7
  → Cambiar → recibe %, actualiza, step 7

Step 7 — Plan de flujo de caja
  Bot genera y envía:
  "📋 Plan de caja — Mayo 2026

   Quincena 1 (día 4 — EMAPTA $3.335.000):
   ✓ Pagar arriendo: -$2.500.000
   ✓ CrediExpress #290742: -$866.000
   ✓ Abono extra snowball: -$200.000
   Queda en mano: $769.000

   Quincena 2 (día 19 — 525 ~$3.000.000):
   ✓ CrediExpress #238105: -$83.000
   ✓ Moto: -$245.000
   ✓ iPhone papá: -$178.000
   ✓ Necesario (mercado, etc.): -$700.000
   ✓ Discrecional: -$600.000
   Queda en mano: $1.194.000

   💰 Excedente proyectado: $1.194.000
   🎁 Tu recompensa si cumples: $59.700 (5%)
   📈 Resto para metas/ahorro: $1.134.300

   ¿Aprobamos este plan?"
  Botones: [Aprobar ✓ | Ajustar algo]
  → Aprobar → step 8
  → Ajustar → vuelve al paso que el usuario indique

Step 8 — Confirmar y escribir
  El Brain llama:
    POST /api/v1/budgets (bulk) con todos los presupuestos del mes
    PATCH /api/v1/financial_context con reward_pct
  Bot: "✅ Plan guardado. Esta noche el agente ya sabe con qué comparar.
        Si ves que algo no cuadra, escríbeme y lo ajustamos."
  PendingAction → status: completed
```

#### Lógica de propuesta automática de presupuestos

Cuando el usuario ya tiene historial:

```python
def proponer_presupuestos(categoria, historial_3_meses, income_total):
    promedio = mean(historial_3_meses)
    # Benchmarks por categoría (basados en finanzas personales Colombia)
    benchmarks = {
        "committed":     0.50,   # máx 50% del ingreso
        "necessary":     0.15,
        "discretionary": 0.10,   # regla 50/30/20 adaptada
        "investment":    0.10,
        "social":        0.05,
    }
    recomendado = min(promedio * 1.05, income_total * benchmarks[categoria])
    return round(recomendado / 1000) * 1000  # redondear a miles
```

---

### Parte 4 — Agente nocturno actualizado

El `revision_nocturna.py` migrado al Brain agrega:

- Consulta `GET /api/v1/summary` al inicio del run
- Si `burn_rate.categories` tiene alertas → las incluye en el mensaje de Telegram
- Si hay `PendingAction` expirado → lo marca como `cancelled` vía API
- Si es día 1 o día 15 → no lanza planning (ya lo hace el scheduler); solo menciona en el resumen si el plan del mes está aprobado o no

---

### Criterios de aceptación

#### Rails API
- [ ] `POST /api/v1/budgets` acepta array y crea/upserta todos los presupuestos del mes
- [ ] `GET /api/v1/summary` retorna el JSON completo con `balance`, `burn_rate`, `debts`, `financial_context`
- [ ] Burn rate usa hora Colombia (UTC-5), no UTC
- [ ] `burn_rate_alert` aparece si `projected > budget × 0.85`
- [ ] `GET /api/v1/summary` retorna `200` aunque no haya presupuestos (omite sección burn_rate)
- [ ] `GET /api/v1/pending_actions/active` retorna el PendingAction activo o `null`
- [ ] `PATCH /api/v1/pending_actions/:id` actualiza `step`, `context`, `status`
- [ ] `PATCH /api/v1/debts/:id` pasa a `paid_off` automáticamente si `current_balance <= 0`
- [ ] `TelegramController` eliminado de Rails; rutas `/telegram/*` eliminadas
- [ ] Tests cubren: sin presupuesto, en alerta (85-100%), sobre presupuesto, PendingAction expirado

#### FastAPI Brain
- [ ] `POST /webhook/telegram` recibe callbacks y mensajes; delega a wizard si hay PendingAction activo
- [ ] Scheduler corre `nightly` a las 11pm Colombia y `planning` el día 1 y 15 a las 8am
- [ ] El webhook responde a Telegram en < 2 segundos (answerCallbackQuery inmediato)
- [ ] Si no hay PendingAction activo, el webhook funciona exactamente igual que el comportamiento actual

#### Wizard de planificación
- [ ] Escenario sin financial_context: onboarding antes del step 1
- [ ] Escenario "Mañana": PendingAction con `expires_at = now + 24h`; al día siguiente reinicia desde step 0
- [ ] Escenario sin respuesta 48h: cron marca PendingAction como `expired`
- [ ] Escenario ajuste en step 5 (discrecional): recalcula el plan de caja en step 7 automáticamente
- [ ] Step 8 escribe todos los budgets vía Rails API en una sola llamada bulk
- [ ] El plan de flujo de caja en step 7 asigna cada gasto a la quincena correcta según `income_day_1` e `income_day_2`
- [ ] Si el excedente proyectado es negativo, step 7 lo muestra en rojo con la categoría que más impacta
- [ ] La recompensa nunca es más del 10% del excedente (cap de seguridad)

#### Agente nocturno migrado
- [ ] Corre desde Railway (Brain), no desde GitHub Actions
- [ ] Incluye alertas de burn rate en el mensaje cuando aplica
- [ ] Menciona si el plan quincenal está aprobado o falta aprobar al inicio del mes

---

## Fase 3 — Deudas y Metas de Ahorro (Sinking Funds)

**Objetivo**: El sistema conoce el pasivo completo y puede calcular cuánto hay que apartar cada mes para gastos futuros conocidos.

**Duración estimada**: 5 días

### Qué se construye

- Migrations: `debts`, `savings_goals`
- Seeds: deudas actuales de Daniel (CrediExpress, TC LifeMiles, iPhone papá, moto)
- Interactor `MonthlyContributionCalculator`:
  ```
  monthly_needed = (target_amount - current_amount) / months_until_target_date
  ```
- Endpoints:
  - `GET /api/v1/debts`
  - `POST /api/v1/debts`
  - `PATCH /api/v1/debts/:id` (para actualizar saldo tras un pago)
  - `GET /api/v1/savings_goals`
  - `POST /api/v1/savings_goals`
  - `PATCH /api/v1/savings_goals/:id`
- El resumen incluye progreso de deudas y metas de ahorro
- Alerta si no se hizo el aporte mensual a una meta de ahorro

### Criterios de aceptación

- [ ] `POST /api/v1/savings_goals` con `target_date` calcula automáticamente `monthly_contribution_needed`
- [ ] Si `target_date` ya pasó o `current_amount >= target_amount`, retorna `422` con mensaje claro
- [ ] `GET /api/v1/summary` incluye sección `savings_goals` con `monthly_target`, `contributed_this_month`, `on_track`
- [ ] `GET /api/v1/summary` incluye sección `debts` con `total_balance`, `monthly_payments`, `payoff_projection`
- [ ] `PATCH /api/v1/debts/:id` actualiza `current_balance`; si llega a 0, status pasa a `paid_off` automáticamente
- [ ] El mensaje de Telegram nocturno menciona si no se hizo el aporte a alguna meta de ahorro
- [ ] Seeds crean las deudas actuales de Daniel con saldos y cuotas reales
- [ ] Tests cubren: meta sin fecha, meta con fecha pasada, meta ya cumplida, deuda en cero

---

## Fase 4 — Contexto Financiero y Plan de Acción

**Objetivo**: El agente conoce la fase financiera del usuario y adapta su coaching en consecuencia. Las recomendaciones dejan de ser genéricas.

**Duración estimada**: 4 días

### Qué se construye

- Migration: `financial_contexts`
- Interactor `FinancialPhaseAdvisor`: lee la fase actual y el excedente del mes y determina qué hacer con él
- Lógica de fases:
  ```
  debt_payoff    → excedente va a deuda con menor saldo (snowball) o mayor interés (avalanche)
  emergency_fund → excedente va al fondo de emergencia hasta cubrir 3 meses de gastos fijos
  investing      → excedente: 15% a inversión, resto libre
  ```
- Endpoints:
  - `GET /api/v1/financial_context`
  - `PATCH /api/v1/financial_context`
- El resumen incluye: `financial_phase`, `monthly_surplus_estimate`, `recommended_action`
- El agente puede actualizar `notes` en el contexto cuando detecta un cambio relevante

### Criterios de aceptación

- [ ] `GET /api/v1/financial_context` retorna la fase, estrategia y notas del usuario
- [ ] `PATCH /api/v1/financial_context` actualiza fase y estrategia; registra `updated_at`
- [ ] `GET /api/v1/summary` incluye `recommended_action` con la deuda o meta a priorizar según la fase
- [ ] En fase `debt_payoff` con estrategia `snowball`: `recommended_action` señala la deuda de menor saldo
- [ ] En fase `debt_payoff` con estrategia `avalanche`: `recommended_action` señala la deuda de mayor tasa
- [ ] Si el excedente estimado del mes es negativo, el summary incluye alerta de déficit proyectado
- [ ] El mensaje de Telegram nocturno incluye la acción recomendada en lenguaje coloquial colombiano
- [ ] Si las deudas llegan a cero, el sistema sugiere transicionar a `emergency_fund`
- [ ] Si el fondo de emergencia cubre 3 meses de comprometido+necesario, sugiere transicionar a `investing`
- [ ] Tests cubren las 4 fases y las 2 estrategias de pago de deuda

---

## Fase 5 — Gamificación

**Objetivo**: El sistema premia el comportamiento consistente, no el resultado perfecto. La motivación extrínseca refuerza el hábito antes de que la intrínseca tome el control.

**Duración estimada**: 4 días

### Qué se construye

- Migrations: `achievements`, `streaks`
- Interactor `StreakUpdater`: se ejecuta al crear/actualizar una transacción
- Interactor `AchievementChecker`: se ejecuta al calcular el resumen mensual
- Seeds: definición de todos los logros disponibles (sin `achieved_at`)
- Endpoints:
  - `GET /api/v1/achievements`
  - `GET /api/v1/streaks`
- Score mensual 0-100 incluido en el resumen

Logros iniciales:

| Código | Nombre | Condición |
|--------|--------|-----------|
| `first_month_tracked` | Primer mes completo | 30 días con al menos 1 registro |
| `no_delivery_month` | Sin delivery | 0 transacciones en subcategoría Delivery en un mes |
| `debt_reduced_10` | Deuda reducida 10% | Saldo total de deudas baja 10% vs mes anterior |
| `under_budget_discretionary` | Discrecional controlado | Gasto discrecional < 90% del presupuesto |
| `emergency_fund_1month` | Primer colchón | Fondo emergencia ≥ 1 mes de gastos fijos |
| `streak_7` | Racha de 7 días | 7 días consecutivos dentro del presupuesto discrecional |
| `streak_30` | Racha de 30 días | 30 días consecutivos |
| `savings_goal_achieved` | Meta cumplida | Cualquier savings_goal llega al 100% |

### Criterios de aceptación

- [ ] Al crear una transacción, `StreakUpdater` evalúa si la racha `under_budget_discretionary` continúa o se rompe
- [ ] `GET /api/v1/streaks` retorna racha actual y mejor racha histórica por tipo
- [ ] `GET /api/v1/achievements` retorna todos los logros; los obtenidos incluyen `achieved_at`
- [ ] `AchievementChecker` corre al calcular el resumen y otorga logros nuevos si aplica
- [ ] Un logro nunca se otorga dos veces al mismo usuario
- [ ] `GET /api/v1/summary` incluye `financial_score` (0-100) con el desglose por componente
- [ ] El mensaje de Telegram nocturno menciona logros nuevos y rachas activas
- [ ] Si se rompe una racha de 7+ días, el mensaje lo menciona (sin juzgar, solo informar)
- [ ] Tests cubren: primer logro, logro duplicado (debe ignorarse), racha que se rompe, racha que continúa

---

## Fase 6 — Analytics y Dashboard

**Objetivo**: Vista de pájaro del comportamiento financiero. Tendencias, comparativas y patrones que el agente puede usar para coaching más sofisticado.

**Duración estimada**: 1 semana

### Qué se construye

- Endpoints de analytics:
  - `GET /api/v1/analytics/monthly_trend?months=6` — evolución mes a mes
  - `GET /api/v1/analytics/category_breakdown?month=&year=` — torta de gastos
  - `GET /api/v1/analytics/top_concepts?month=&year=&limit=10` — top 10 conceptos
  - `GET /api/v1/analytics/income_vs_expense?months=6` — ingresos vs gastos
  - `GET /api/v1/analytics/debt_payoff_projection` — proyección de liquidación de deudas
- Interactor `MonthlyTrendAnalyzer`
- Interactor `DebtPayoffProjector`

### Criterios de aceptación

- [ ] `GET /api/v1/analytics/monthly_trend?months=6` retorna array con 6 meses: income, total_spent, score, surplus para cada uno
- [ ] `GET /api/v1/analytics/category_breakdown` retorna cada categoría con: amount, pct_of_total, vs_previous_month
- [ ] `GET /api/v1/analytics/top_concepts` retorna los conceptos más frecuentes o de mayor monto (parámetro `sort_by=frequency|amount`)
- [ ] `GET /api/v1/analytics/debt_payoff_projection` retorna mes estimado de liquidación total bajo la estrategia actual
- [ ] Todos los endpoints retornan `200` con array vacío si no hay datos (nunca `500`)
- [ ] El resumen nocturno incluye comparativa vs mes anterior en las categorías donde hay diferencia significativa (>15%)
- [ ] Performance: todos los endpoints de analytics responden en <500ms con 12 meses de datos
- [ ] Tests cubren: sin datos históricos, 1 mes de datos, 6+ meses de datos

---

## Definición de done global del módulo

El módulo Finanzas se considera completo cuando:

- [ ] Todas las fases 1-6 tienen sus criterios de aceptación en verde
- [ ] `bundle exec rspec` pasa al 100% para el dominio finanzas
- [ ] `bundle exec rubocop` retorna 0 offenses
- [ ] Swagger documenta todos los endpoints de finanzas en `/api-docs`
- [ ] El agente nocturno lleva 7 días operando exclusivamente con la API (sin Excel ni Dropbox)
- [ ] El Excel puede generarse on-demand como export, pero ya no es la fuente de verdad
- [ ] Un usuario nuevo puede registrarse, crear sus categorías y registrar su primer gasto en menos de 5 minutos
