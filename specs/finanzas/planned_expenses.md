# planned_expenses

> Última actualización: 2026-04-23

## Qué es

`planned_expenses` es la fuente de verdad para gastos futuros previsibles que todavía no son transacciones reales ni obligaciones mensuales fijas.

Representa intención o previsión operativa, no ejecución contable.

Ejemplos:

- SOAT
- tecnomecánica
- impuesto de rodamiento
- mantenimiento de moto
- viaje
- pantalón
- zapatos
- compra planificada

## Qué no es

`planned_expenses` no reemplaza:

- `transactions`
- `recurring_obligations`
- `debts`
- `investments`

Tampoco dispara automatizaciones complejas en esta fase.

## Por qué existe

El sistema ya tenía `sinking_funds` para apartar dinero mes a mes, pero faltaba una entidad explícita para listar y seguir gastos futuros previsibles aunque todavía no exista una reserva asociada.

Eso permite:

- planear próximos gastos sin convertirlos en deuda
- distinguir una obligación mensual de un evento futuro puntual
- preservar semántica por `category_id` y `subcategory_id`
- dejar trazabilidad de estado (`planned`, `executed`, `cancelled`)

## Diferencia frente a otras entidades

### `transactions`

- `transactions` registra lo que ya ocurrió
- `planned_expenses` registra lo que todavía no ha ocurrido

No hay creación automática de transacción desde un `planned_expense` en esta fase.

### `recurring_obligations`

- `recurring_obligations` es la fuente de verdad del impacto mensual fijo en caja
- `planned_expenses` representa eventos futuros previsibles, no necesariamente mensuales ni recurrentes

Ejemplo:

- cuota mensual de crédito moto → `recurring_obligations`
- próximo SOAT → `planned_expenses`

### `debts`

- `debts` modela el estado estructural del pasivo
- `planned_expenses` no es pasivo estructural

Si un gasto futuro termina financiándose con deuda, ese cambio se modela después en la entidad correspondiente. No se anticipa artificialmente en esta tabla.

### `investments`

- `investments` modela construcción estructural de activo o patrimonio
- `planned_expenses` modela gasto futuro planificado

Una compra planeada no se convierte en inversión por tener fecha objetivo.

## Fuentes de verdad

- flujo mensual → `recurring_obligations`
- estado deuda → `debts`
- estado inversión → `investments`
- planeación futura → `planned_expenses`
- semántica conductual → `category_id` + `subcategory_id`

## Modelo mínimo actual

```sql
planned_expenses
  id
  user_id
  account_id
  name
  amount_estimated
  target_date
  planning_type
  status
  category_id
  subcategory_id
  notes
  created_at
  updated_at
```

### `planning_type`

Valores iniciales:

- `mandatory_one_off`
- `irregular_maintenance`
- `wish`
- `planned_purchase`

### `status`

Valores iniciales:

- `planned`
- `executed`
- `cancelled`

## Límites de esta fase

- no hay creación automática de transacciones
- no hay reservas automáticas
- no hay integración total con `monthly_plan`
- no hay cleanup destructivo de campos legacy
- no reemplaza `sinking_funds`; una reserva puede existir o no, independientemente del gasto planificado
