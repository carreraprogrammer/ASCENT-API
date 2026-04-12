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

## Fase 2 — Presupuestos y Alertas de Burn Rate

**Objetivo**: El agente puede advertirte antes de que te pases del presupuesto, no después.

**Duración estimada**: 4 días

### Qué se construye

- Migration: `budgets`
- Interactor `BurnRateAnalysis`: calcula proyección al fin de mes por categoría
- Endpoints:
  - `GET /api/v1/budgets?month=&year=`
  - `POST /api/v1/budgets`
  - `PATCH /api/v1/budgets/:id`
  - `GET /api/v1/summary?month=&year=` (versión inicial)
- Lógica de burn rate:
  ```
  gasto_proyectado = (gasto_real / días_transcurridos) × días_del_mes
  alerta si gasto_proyectado > presupuesto × 0.85
  ```
- El resumen nocturno incluye alertas de burn rate por categoría

### Criterios de aceptación

- [ ] `POST /api/v1/budgets` crea presupuesto para una categoría y mes/año
- [ ] `GET /api/v1/summary` incluye para cada categoría: `budget`, `spent`, `projected`, `pct`, `on_track`
- [ ] Si `projected > budget × 0.85`, el campo `burn_rate_alert` contiene un mensaje en español con los números concretos
- [ ] Si `projected > budget`, `on_track` es `false`
- [ ] El mensaje de Telegram nocturno menciona explícitamente las categorías en alerta con los montos proyectados
- [ ] El cálculo de días usa la fecha actual en hora Colombia (UTC-5), no UTC
- [ ] `GET /api/v1/summary` retorna `200` aunque no haya presupuestos definidos (muestra solo el gasto, sin proyección)
- [ ] Tests cubren: sin presupuesto, dentro del presupuesto, en zona de alerta (85-100%), sobre presupuesto (>100%)

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
