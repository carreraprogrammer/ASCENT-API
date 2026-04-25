# Historial de Planes y Ejecución Mensual

> Estado: Backend implementado y desplegado. Front-end y ProposeBudget pendientes.
> Última actualización: 2026-04-25

---

## 1. Problema que resuelve

Los planes mensuales ya se guardan con `month` + `year` como clave única, pero el sistema
no los expone como historial ni registra qué pasó realmente contra lo planeado.

Consecuencias hoy:
- El usuario no puede ver el plan de abril en diciembre.
- `ProposeBudget` no aprende de meses anteriores — propone siempre desde cero con los
  mismos rangos colombianos o el historial bruto de transacciones.
- No existe cierre de mes: un plan confirmado en enero nunca queda "sellado" con sus
  resultados reales.

---

## 2. Principio de diseño

**Un plan tiene dos mitades: intención y ejecución.**

- La intención se captura al confirmar (`confirmed_at`).
- La ejecución se captura al cerrar el mes (`closed_at`) — compara lo planeado
  contra lo que realmente ocurrió en transacciones.

El cierre es idempotente: se puede re-cerrar si llegan transacciones tardías.
Un plan cerrado no es editable, pero sí re-cerrable.

---

## 3. Modelo de datos

### 3.1 Nuevos campos en `monthly_financial_plans`

```ruby
add_column :monthly_financial_plans, :income_actual,        :integer, default: 0, null: false
add_column :monthly_financial_plans, :expense_actual,       :integer, default: 0, null: false
add_column :monthly_financial_plans, :execution_snapshot,   :jsonb,   default: {}, null: false
add_column :monthly_financial_plans, :closed_at,            :datetime
```

**No se agrega `status: "closed"`** — se usa `closed_at.present?` como señal de cierre.
El campo `status` sigue siendo `draft | confirmed | superseded`.

### 3.2 Estructura de `execution_snapshot`

```json
{
  "income_actual": 6400000,
  "expense_actual": 5120000,
  "categories": [
    {
      "code": "housing",
      "name": "Vivienda",
      "budgeted": 1200000,
      "actual": 1200000,
      "variance": 0,
      "variance_pct": 0
    },
    {
      "code": "discretionary",
      "name": "Discrecional",
      "budgeted": 400000,
      "actual": 512000,
      "variance": 112000,
      "variance_pct": 28
    }
  ],
  "overflow_applied": "debt",
  "overflow_amount": 280000,
  "closed_at": "2026-04-30T23:59:59Z"
}
```

**Reglas de cálculo:**
- `income_actual` = suma de transacciones `transaction_type: income, status: confirmed`
  del mes.
- `expense_actual` = suma de transacciones `transaction_type: expense, status: confirmed`
  del mes.
- `variance` = `actual - budgeted` (positivo = sobrepasó, negativo = ahorró).
- `variance_pct` = `(variance / budgeted * 100).round` — `nil` si `budgeted == 0`.
- `overflow_amount` = max(`income_actual - expense_actual - recurring_obligations_total
  - debt_minimums_total - protected_buffer_amount`, 0).

---

## 4. Interactor: `CloseMonthlyPlan`

```
app/domains/finanzas/interactors/close_monthly_plan.rb
```

### Firma

```ruby
CloseMonthlyPlan.new.call(account_id:, plan_id:)
```

### Lógica

1. Cargar el plan. Lanzar `PlanNotFound` si no existe o no pertenece al `account_id`.
2. Lanzar `PlanNotConfirmed` si `confirmed_at.nil?` — solo se cierran planes confirmados.
3. Calcular `income_actual` y `expense_actual` desde transacciones confirmed del mes.
4. Cargar budgets del mes (`Budget.where(account_id:, month:, year:)`).
5. Calcular gasto real por `category_id` desde transacciones (query agrupado).
6. Construir el array `categories` cruzando budgets con actuals.
7. Calcular `overflow_amount`.
8. Llamar `plan_repo.close(plan_id, snapshot)`.
9. Retornar el plan actualizado.

### Idempotencia

Si el plan ya tiene `closed_at`, el interactor re-computa y sobreescribe — así las
transacciones tardías quedan reflejadas.

---

## 5. Repository: nuevos métodos

```ruby
# Retorna todos los planes del account ordenados por año/mes desc
def list_history(account_id:, page: 1, per_page: 12)
  records = ::MonthlyFinancialPlan
    .where(account_id: account_id)
    .order(year: :desc, month: :desc)
  total = records.count
  paged = records.offset((page - 1) * per_page).limit(per_page)
  {
    data: paged.map { |r| map_to_entity(r) },
    meta: { total:, page:, per_page:, total_pages: (total.to_f / per_page).ceil }
  }
end

# Cierra el plan: guarda execution_snapshot, income_actual, expense_actual, closed_at
def close(id, snapshot:, income_actual:, expense_actual:, account_id:)
  record = ::MonthlyFinancialPlan.find_by(id: id, account_id: account_id)
  raise ActiveRecord::RecordNotFound unless record
  record.update!(
    execution_snapshot: snapshot,
    income_actual:      income_actual,
    expense_actual:     expense_actual,
    closed_at:          Time.current
  )
  map_to_entity(record)
end

# Retorna los últimos N planes cerrados (para ProposeBudget)
def last_closed(account_id:, limit: 3)
  ::MonthlyFinancialPlan
    .where(account_id: account_id)
    .where.not(closed_at: nil)
    .order(year: :desc, month: :desc)
    .limit(limit)
    .map { |r| map_to_entity(r) }
end
```

También agregar al `map_to_entity` los cuatro nuevos campos:
`income_actual`, `expense_actual`, `execution_snapshot`, `closed_at`.

---

## 6. Controller: cambios en `MonthlyPlansController`

### `index` — historial paginado

```ruby
def index
  result = repo.list_history(
    account_id: current_account.id,
    page:       (params[:page] || 1).to_i,
    per_page:   (params[:per_page] || 12).to_i
  )
  render json: result
end
```

### `close` — cerrar el mes

```ruby
def close
  return unless require_scope!("budgets:update")
  plan = Finanzas::Interactors::CloseMonthlyPlan.new.call(
    account_id: current_account.id,
    plan_id:    params[:id].to_i
  )
  render json: { data: plan }
rescue Finanzas::Errors::PlanNotFound => e
  render json: { errors: [{ status: "404", detail: e.message }] }, status: :not_found
rescue Finanzas::Errors::PlanNotConfirmed => e
  render json: { errors: [{ status: "422", detail: e.message }] }, status: :unprocessable_entity
end
```

### Routes

```ruby
resources :monthly_plans, only: [:index, :update] do
  collection do
    get  :current
    get  :propose
    get  :wizard_data
    post :generate
  end
  member do
    post :confirm
    post :close     # NUEVO
  end
end
```

---

## 7. `ProposeBudget`: usar historial

### Qué cambia

`ProposeBudget#call` recibe los últimos 3 planes cerrados y los usa para:

1. **Ajustar límites de categoría**: si una categoría tiene `variance_pct > 15%` en
   dos de los últimos tres meses, el límite propuesto sube al promedio real en lugar del
   histórico bruto.
2. **Generar `historical_patterns`**: lista de patrones detectados que el wizard muestra
   al usuario ("En los últimos 3 meses gastaste 28% más de lo planeado en Discrecional").
3. **Ajustar `income_accuracy`**: si `income_actual` < `base_budget_income` en los
   últimos dos meses, agrega advertencia de sobreestimación de ingreso.

### Cambio en la firma

```ruby
# Agregar parámetro opcional; el interactor lo busca solo si no se pasa
def call(account_id:, month:, year:, include_variable: false, plan_history: nil)
  history = plan_history || plan_history_repo.last_closed(account_id: account_id, limit: 3)
  # ...
  patterns = extract_patterns(history, categories)
  # ...
  { ..., historical_patterns: patterns }
end
```

### Estructura de `historical_patterns`

```json
[
  {
    "category_code": "discretionary",
    "category_name": "Discrecional",
    "pattern": "consistently_over",
    "avg_variance_pct": 24,
    "months_checked": 3,
    "suggestion": "Ajustamos el límite propuesto a $520.000 basado en tu gasto real."
  },
  {
    "category_code": null,
    "pattern": "income_overestimated",
    "avg_shortfall": 350000,
    "months_checked": 2,
    "suggestion": "En los últimos 2 meses el ingreso real fue menor al planeado. Usamos un ingreso base más conservador."
  }
]
```

Patrones detectables:
| Código | Condición |
|--------|-----------|
| `consistently_over` | `variance_pct > 15` en ≥ 2 de los últimos 3 meses |
| `consistently_under` | `variance_pct < -20` en ≥ 2 de los últimos 3 meses (sobra presupuesto) |
| `income_overestimated` | `income_actual < base_budget_income * 0.95` en ≥ 2 meses |
| `overflow_never_applied` | `overflow_applied: null` en todos los meses cerrados |

---

## 8. Errores nuevos

```ruby
# app/domains/finanzas/errors.rb
class PlanNotFound     < StandardError; end
class PlanNotConfirmed < StandardError; end
```

---

## 9. Endpoints resultantes

```
GET  /api/v1/monthly_plans                    # historial paginado (CAMBIA de solo-current)
GET  /api/v1/monthly_plans/current            # plan del mes vigente (sin cambio)
GET  /api/v1/monthly_plans/propose            # propuesta calculada (ahora incluye historical_patterns)
POST /api/v1/monthly_plans/:id/close          # NUEVO — cierra el mes y guarda ejecución
```

---

## 10. Estado de implementación

| Componente | Estado |
|-----------|--------|
| Spec documentado | ✅ |
| Migración: 4 campos nuevos en `monthly_financial_plans` | ✅ |
| `CloseMonthlyPlan` interactor | ✅ |
| `MonthlyFinancialPlanRepository`: `list_history`, `close`, `last_closed` | ✅ |
| `MonthlyPlansController#index` — historial paginado | ✅ |
| `MonthlyPlansController#close` — acción nueva | ✅ |
| Routes: `POST /monthly_plans/:id/close` | ✅ |
| Errores: `PlanNotFound`, `PlanNotConfirmed` | ✅ |
| `ProposeBudget`: lee historial, genera `historical_patterns` | ⬜ |
| Front-end: lista de historial de planes | ⬜ |
| Front-end: detalle plan con plan vs actual | ⬜ |
| Front-end: botón "Cerrar mes" en plan confirmado | ⬜ |
