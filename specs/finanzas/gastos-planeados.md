# Gastos Planeados

> Estado: 🟡 CRUD implementado — integración con plan mensual pendiente
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

## Uso desde backend

- endpoint `GET /api/v1/planned_expenses`
- endpoint `POST /api/v1/planned_expenses`
- endpoint `PATCH /api/v1/planned_expenses/:id`
- persistencia mínima en `PlannedExpense`
- validación de coherencia entre `category_id` y `subcategory_id`

## Uso desde UI

Superficie mínima actual:

- ruta `/planned-expenses`
- listado con nombre, monto estimado, fecha objetivo, tipo, estado y clasificación
- modal para crear
- modal para editar
- cambio de estado vía edición (`planned`, `executed`, `cancelled`)
- acciones rápidas en la card para marcar `executed` o `cancelled` sin abrir el formulario

## Uso desde el agente

Capacidad mínima actual del Brain:

- `get_planned_expenses`
- `create_planned_expense`
- `update_planned_expense`

Regla operativa documentada en prompts:

- si el gasto es futuro, previsible y todavía no ocurrió, no se registra como transacción
- si no es un compromiso mensual fijo, no se mete en `recurring_obligations`
- debe clasificarse con `category_id` y `subcategory_id`

## Estado real de la fase

### Implementado

- backend de `planned_expenses`
- relación explícita `recurring_obligations.source_type/source_id`
- backfill conservador para obligaciones ligadas a deuda

### Expuesto en UI

- página de `planned_expenses`
- visibilidad del vínculo deuda ↔ obligación recurrente en deudas y recurrentes

### Disponible para agente

- tools y adapter para listar/crear/actualizar `planned_expenses`
- lectura del vínculo deuda ↔ obligación por `source_type/source_id`
- unlink explícito de deuda ↔ obligación vía `update_recurring_obligation` con `source_type=null` y `source_id=null`

### Pendiente futuro

- linking manual más completo entre deuda y obligación desde UI
- integración profunda con `monthly_plan`
- automatización opcional entre `planned_expenses` y `sinking_funds`
- soporte estructural real para `investments`

### Prioridad siguiente

La siguiente ejecución debe hacer que `planned_expenses` deje de ser solo un CRUD y entre al loop vivo del plan mensual:

- cálculo de aporte mensual sugerido dentro del wizard
- traducción clara hacia `sinking_funds`
- uso por el agente como gasto futuro a fondear, no como transacción real

Ver:

- [living-budget.md](./living-budget.md)

## Reglas operativas del sistema

- si ya ocurrió, es `transaction`
- si impacta todos los meses la caja, es `recurring_obligation`
- si describe estado estructural del pasivo, es `debt`
- si es un gasto futuro previsible que todavía no ocurrió y no es mensual, es `planned_expense`

## Phase Closure Checklist

- backend de `planned_expenses` operativo
- UI de `planned_expenses` operable con create/edit/status
- vínculo deuda ↔ obligación visible
- vínculo deuda ↔ obligación operable desde UI
- fallback legacy `allocatable_*` todavía soportado
- agente capaz de leer, crear y actualizar esta fase del dominio
