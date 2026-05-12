# Cash Flow Runway — Salud Financiera de Corto Plazo

> Estado: 🟡 spec activo — pendiente de implementación
> Última actualización: 2026-05-12

---

## Objetivo

Reemplazar el modelo de liquidez anterior (`free_after_obligations`, `safe_to_deploy` y derivados) por un modelo que responda la pregunta real que se hace cualquier persona antes de revisar su cuenta:

> **"¿Me alcanza hasta que me llegue la plata?"**

El modelo anterior comparaba el presupuesto completo del ciclo contra la caja proyectada. Era correcto en teoría pero inútil en la práctica: mezclaba compromisos fijos con presupuesto flexible, producía cifras negativas que no explicaban nada accionable, y no tenía en cuenta la fecha de los compromisos dentro del ciclo.

El nuevo modelo tiene dos preguntas concretas:

1. **¿Me alcanza para los gastos del día a día hasta el próximo ingreso?** → runway operativo
2. **¿Tengo liquidez para cubrir los compromisos que vencen antes de que llegue la plata?** → brecha de compromiso

---

## Modelo conceptual

### Variables de entrada

| Variable | Fuente | Descripción |
|----------|--------|-------------|
| `confirmed_balance` | `transactions` (income - expense, confirmed) | Saldo real en cuenta hoy |
| `daily_necessary_burn` | `transactions` (últimos 30 días, categoría `necessary`) | Gasto diario promedio en necesarios |
| `days_to_next_income` | `income_sources.expected_day_from` | Días hasta el próximo evento de ingreso |
| `next_income_day` | `income_sources.expected_day_from` (más próximo) | Día del mes en que llega la siguiente quincena |
| `committed_before_next_income` | `recurring_obligations` con `due_day <= next_income_day` no cubiertos | Obligaciones fijas que vencen antes de que llegue la plata |

### Cálculos derivados

```
runway_days            = confirmed_balance / daily_necessary_burn

available_after_commit = confirmed_balance - committed_before_next_income

effective_runway_days  = available_after_commit / daily_necessary_burn

buffer_days            = effective_runway_days - days_to_next_income

commitment_gap         = confirmed_balance
                       - committed_before_next_income
                       - (daily_necessary_burn × days_to_next_income)
```

### Clasificación de salud (`health_status`)

```
critical:    commitment_gap < 0
             → No alcanza: los compromisos fijos más el burn diario superan el saldo actual

warning:     commitment_gap >= 0  AND  buffer_days < 2
             → Alcanza justo, pero sin margen de maniobra

comfortable: buffer_days >= 2
             → Cubre los compromisos y el burn, y sobran al menos 2 días de colchón
```

### Ejemplo del mundo real

```
confirmed_balance            = $350.000
daily_necessary_burn         = $30.000    (mercado ~$90k/semana + almuerzo ~$18k/día)
days_to_next_income          = 8          (hoy día 12, quincena llega día 20)
committed_before_next_income = $200.000   (crédito vence día 16)

commitment_gap = $350.000 - $200.000 - ($30.000 × 8)
              = $350.000 - $200.000 - $240.000
              = -$90.000

health_status = "critical"
heroPhrase    = "Estás en rojo antes del día 20."
```

```
confirmed_balance            = $350.000
committed_before_next_income = $0         (ningún compromiso vence antes del día 20)

commitment_gap = $350.000 - $0 - $240.000 = $110.000
buffer_days    = $110.000 / $30.000 = 3.7 días

health_status = "comfortable"
heroPhrase    = "Vas tranquilo hasta el día 20."
```

---

## Taxonomía de prescindibilidad

El agente necesita razonar sobre qué gastos pueden reducirse en un estado `critical`. La taxonomía usa la misma estructura de `category_type` que ya existe en el sistema, añadiendo un nivel de prescindibilidad:

| Nivel | Nombre | `category_type` aplicables | Ejemplos | ¿Reducible en crisis? |
|-------|--------|---------------------------|----------|----------------------|
| 0 | Supervivencia | `committed`, `necessary` | Mercado, transporte al trabajo, arriendo, medicamentos | No |
| 1 | Calidad de vida | `necessary`, `investment` | Gimnasio, celular, cursos activos | Suspendible |
| 2 | Confort | `discretionary`, `social` | Restaurantes, delivery, streaming, salidas | Sí |

**Regla para `daily_necessary_burn`:** usa transacciones de los últimos 30 días con `category_type = 'necessary'`. No incluye `committed` porque esos tienen `due_day` explícito y se capturan en `committed_before_next_income`.

**Regla para prescindibilidad a nivel de subcategoría:** el agente infiere el nivel por `subcategory.code`. No se necesita un campo nuevo en la base de datos — la subcategoría ya tiene semántica suficiente. Ejemplos:

- `mercado`, `gasolina`, `transporte`, `salud` → Nivel 0
- `gym`, `celular`, `cursos` → Nivel 1
- `restaurantes`, `delivery`, `streaming`, `ocio` → Nivel 2

---

## Arista 1 — Backend

### Nuevo interactor: `CashFlowRunway`

**Archivo:** `app/domains/finanzas/interactors/cash_flow_runway.rb`

**Responsabilidades:**
- Recibe datos ya cargados por el controller (sin queries propias)
- Calcula todas las variables del modelo
- Retorna un hash listo para el frontend y el agente

**Inputs:**
```ruby
def call(
  confirmed_balance:,            # Integer
  transactions_last_30_days:,    # Array<Hash> — solo gastos confirmed, con category_type
  income_sources:,               # Array<Hash> — fuentes activas con expected_day_from
  recurring_obligations:,        # Array<Hash> — obligaciones activas con due_day
  realized_obligations:,         # Hash — obligation_id => amount_paid (este ciclo)
  today:                         # Date
)
```

**Output:**
```ruby
{
  confirmed_balance:              Integer,
  daily_necessary_burn:           Integer,   # promedio diario, últimos 30 días, cat 'necessary'
  days_to_next_income:            Integer,   # días hasta expected_day_from más próximo
  next_income_day:                Integer,   # día del mes
  committed_before_next_income:   Integer,   # suma de obligaciones con due_day <= next_income_day no cubiertas
  committed_obligations:          Array,     # lista de obligaciones capturadas, con due_day y amount
  runway_days:                    Integer,   # confirmed_balance / daily_necessary_burn
  effective_runway_days:          Integer,   # (confirmed_balance - committed) / daily_burn
  buffer_days:                    Integer,   # effective_runway_days - days_to_next_income
  commitment_gap:                 Integer,   # confirmed_balance - committed - (burn × days)
  health_status:                  String,    # "comfortable" | "warning" | "critical"
  burn_window_days:               Integer,   # días de historial usados (target: 30)
  has_sufficient_history:         Boolean    # false si < 14 días de transacciones en ventana
}
```

**Regla de historial insuficiente:**
Si hay menos de 14 días de transacciones `necessary` en los últimos 30 días, `has_sufficient_history = false` y el interactor usa el historial disponible como aproximación. El frontend muestra el estado como estimado.

**Integración en `SummaryController`:**
`GET /api/v1/summary` expone el resultado como campo `cash_flow_runway`. El campo `liquidity` existente se elimina en la misma iteración.

---

### Campos del plan que cambian

| Campo | Cambio |
|-------|--------|
| `protected_buffer_amount` | **Eliminar** del plan y de `GenerateMonthlyFinancialPlan` |
| `discretionary_limit` | **Conservar** — sigue siendo útil para el plan estratégico mensual, pero se elimina de cualquier cálculo de liquidez de corto plazo |

---

### Campos eliminados del `SummaryController`

Estos campos se eliminan del response de `GET /api/v1/summary`:

```
liquidity.free_after_obligations
liquidity.safe_to_deploy
liquidity.deployable_this_cycle
liquidity.cash_flow_gap
liquidity.next_cycle_obligations
liquidity.protected_buffer
liquidity.buffer_status
overflow_status.deployable_overflow
overflow_status.blocked_by_liquidity
financial_context.monthly_surplus_estimate
financial_context.recommended_action
```

El campo `liquidity` completo se reemplaza por `cash_flow_runway`.

---

## Arista 2 — UX/UI

### Hero (Zona 0) — nueva semántica

El hero responde exactamente las preguntas del modelo:

**Frase principal** (`heroPhrase`) según `health_status`:

| Estado | Frase |
|--------|-------|
| `comfortable` | "Vas tranquilo hasta el día {next_income_day}." |
| `warning` | "Alcanzas justo, sin margen de maniobra." |
| `critical` (solo burn) | "El día a día te consume antes del {next_income_day}." |
| `critical` (compromiso) | "Hay un compromiso que no alcanzas a cubrir." |
| sin plan / sin historial | "Sin historial suficiente para calcular." |

**Subtítulo** (`heroSubtitle`) — agrega el número concreto:

| Estado | Subtítulo |
|--------|-----------|
| `comfortable` | "Tienes {buffer_days} días de colchón sobre tus necesarios." |
| `warning` | "Te sobran {formatCurrency(commitment_gap)} — cualquier imprevisto cambia el estado." |
| `critical` | "Te faltan {formatCurrency(abs(commitment_gap))} antes del día {next_income_day}." |

**Barra temporal** — sin cambios conceptuales. Sigue mostrando hoy → próxima quincena.

**Números del hero:**
- "En tu cuenta" → `confirmed_balance`
- "Comprometido antes del {next_income_day}" → `committed_before_next_income` (solo si > 0)
- "Margen" → `commitment_gap` (con color según estado)

**Estado sin historial suficiente:**
Si `has_sufficient_history = false`, mostrar subtítulo "Estimado — menos de 14 días de historial" con opacidad reducida en los números.

---

## Arista 3 — Agente

### Qué campos leer

El agente deja de referenciar `safe_to_deploy`, `free_after_obligations` y todos los campos eliminados. Los reemplaza por:

```
cash_flow_runway.health_status         → estado de salud operativo
cash_flow_runway.commitment_gap        → brecha concreta en pesos
cash_flow_runway.committed_obligations → lista de compromisos con fechas
cash_flow_runway.daily_necessary_burn  → calibración del gasto diario
cash_flow_runway.days_to_next_income   → contexto temporal
```

### Comportamiento por estado

**`comfortable`:**
El agente puede hablar de estrategia (deudas, ahorro, overflow). No hay urgencia operativa.

**`warning`:**
El agente menciona que el margen es estrecho. Antes de cualquier recomendación estratégica, confirma que no hay gastos imprevistos planificados antes del próximo ingreso.

**`critical`:**
El agente activa el flujo de resolución de brecha:

1. **Calcula la brecha:** `abs(commitment_gap)`
2. **Revisa bolsillos disponibles** (`sinking_funds` con `current_amount > 0`)
3. **Identifica gastos prescindibles** en los próximos `days_to_next_income` días:
   - Subcategorías Nivel 1 y Nivel 2 con transacciones recurrentes en ese período
   - Usa historial de los últimos 30 días para estimar qué podría repetirse
4. **Propone acción concreta:**
   - Si bolsillos cubren la brecha: "Puedes complementar con $X del bolsillo {nombre}."
   - Si gastos prescindibles cubren la brecha: "Si pausas {gasto}, recuperas $X y quedas con margen de $Y."
   - Si ninguna opción cubre: "Necesitas revisar el compromiso del día {due_day} — ¿puedes negociar la fecha?"

### Lo que el agente NO hace en estado `critical`

- No recomienda abonar a deudas
- No habla de estrategia de ahorro
- No menciona overflow ni excedente
- No da recomendaciones que ignoren la brecha operativa

---

## Casos borde

| Caso | Comportamiento |
|------|---------------|
| `daily_necessary_burn = 0` (usuario nuevo) | `has_sufficient_history = false`, usar referencia de $30.000/día para Colombia como estimado hasta tener datos |
| No hay `income_sources` activas | `days_to_next_income = null`, no se puede calcular `committed_before_next_income` — exponer `health_status = null` con mensaje "Registra tus fuentes de ingreso para ver tu estado" |
| Todas las obligaciones ya están cubiertas | `committed_before_next_income = 0`, el modelo funciona solo con runway operativo |
| `confirmed_balance = 0` | `health_status = "critical"` directamente, sin cálculo de runway |
| Próximo ingreso es hoy o ya pasó | `days_to_next_income = 0`, `committed_before_next_income = 0`, `commitment_gap = confirmed_balance` — estado determinado solo por balance vs burn en lo que resta del día |

---

## Campos que desaparecen del contrato API

Esta es la lista definitiva de campos a eliminar del response de `GET /api/v1/summary`. El Brain debe actualizarse antes o en la misma iteración que el backend.

```
liquidity                                (bloque completo → reemplazado por cash_flow_runway)
overflow_status.deployable_overflow
overflow_status.blocked_by_liquidity
financial_context.monthly_surplus_estimate
financial_context.recommended_action
monthly_plan.protected_buffer_amount
```

---

## Plan de ejecución

```
1. Nuevo interactor CashFlowRunway (sin queries, puro cálculo)
2. SummaryController: cargar transactions_last_30_days y pasar al interactor
3. SummaryController: exponer cash_flow_runway, eliminar campos obsoletos
4. Frontend: actualizar tipos TypeScript (LiquidityProjection → CashFlowRunway)
5. Frontend: rewire Zona 0 del hero con nueva semántica
6. Agente: actualizar system prompt para referenciar nuevos campos
7. Agente: implementar flujo de resolución de brecha en estado critical
8. Eliminar LiquidityProjection (o marcar como deprecated hasta confirmar que el Brain no la referencia)
```

---

## Fuentes de verdad que no cambian

- flujo mensual fijo → `recurring_obligations` (con `due_day`)
- ingresos estructurales → `income_sources` (con `expected_day_from`)
- saldo real → `transactions` (confirmed, income - expense)
- reservas → `sinking_funds`
- estado estructural del pasivo → `debts`
