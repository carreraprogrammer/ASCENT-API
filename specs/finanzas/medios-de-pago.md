# Medios de Pago y Tarjetas de Crédito

> Estado: 🔲 spec listo — pendiente de implementar (Fase 3.5)
> Última actualización: 2026-04-24

---

## 1. Problema que resuelve

El sistema captura transacciones desde múltiples fuentes (Telegram, email, entrada manual). Hoy no distingue si una transacción salió de débito, crédito o efectivo. Esto genera un problema específico con tarjetas de crédito:

1. El usuario registra compras individuales durante la semana con tarjeta de crédito.
2. El viernes paga el saldo acumulado desde su cuenta débito.
3. Davivienda envía un email: "abono de $92.000 a tu tarjeta desde tu cuenta débito."
4. El agente nocturno captura ese email y crea una nueva transacción de gasto por $92.000.
5. Resultado: el gasto está duplicado — las compras individuales + el pago.

**La causa raíz:** el sistema no sabe que el pago a tarjeta no es un gasto nuevo — es la extinción de una deuda ya registrada.

---

## 2. Principio de diseño

Una compra con tarjeta de crédito es un gasto que ocurre en el momento de la compra, no en el momento del pago. El pago al banco es una transferencia entre un pasivo (la deuda acumulada con la tarjeta) y el activo (la cuenta bancaria). No debe contarse como gasto nuevo.

**Regla:** `payment_source = credit_card` → el gasto se registra al comprar, con estado `pending`. El pago al banco cambia el estado a `settled`. Nunca crea una segunda transacción de gasto.

---

## 3. Modelo de datos

### 3.1 Dos nuevos campos en `transactions`

```ruby
add_column :transactions, :payment_source, :string
# Valores: "credit_card" | "debit" | "cash" | nil (legacy/desconocido)

add_column :transactions, :credit_card_status, :string
# Valores: "pending" | "settled" | nil
# Solo relevante cuando payment_source = "credit_card"
```

**Regla de integridad:**
- Si `payment_source = "credit_card"` → `credit_card_status` debe ser `"pending"` o `"settled"`.
- Si `payment_source != "credit_card"` → `credit_card_status` es nil.
- Transacciones legacy (`payment_source = nil`) se tratan como débito para efectos de cash flow.

### 3.2 Sin tabla nueva

No se crea una tabla `payment_methods`. Los tres tipos (`credit_card`, `debit`, `cash`) son universales y no requieren configuración por usuario. El "pool de crédito pendiente" es un cómputo:

```sql
SELECT SUM(amount)
FROM transactions
WHERE account_id = :account_id
  AND payment_source = 'credit_card'
  AND credit_card_status = 'pending'
  AND month = :month
  AND year = :year
```

### 3.3 Relación con el módulo de deudas

El módulo de deudas (`debts`) maneja el saldo estructural de la tarjeta: balance total, estrategia snowball/avalanche, cuota mínima, proyección de pago. Eso no cambia.

El pool de pendientes maneja las compras del ciclo actual que aún no fueron pagadas al banco. Son dos niveles del mismo fenómeno:

| Módulo | Granularidad | Propósito |
|--------|-------------|-----------|
| `debts` | Saldo total de la tarjeta | Estrategia de pago, snowball, proyección |
| `credit_card_status` en transactions | Compra individual | Deduplicar el abono mensual |

No se cruzan. No es necesario vincularlos.

---

## 4. Flujo de registro

### 4.1 Entrada manual / chat agent

Cuando el usuario registra un gasto, el sistema confirma el medio de pago antes de guardar:

**En UI:** tras ingresar monto y categoría, aparecen tres botones:
```
[ Tarjeta de Crédito ]  [ Débito / Transferencia ]  [ Efectivo ]
```

**En chat (Telegram o web):** el agente pregunta "¿con qué pagaste?" si el usuario no lo especifica. Si lo especifica en el mensaje ("pagué con la Avianca"), el agente extrae el medio de pago sin preguntar.

Al guardar:
- `debit` o `cash` → transacción normal, sin `credit_card_status`
- `credit_card` → transacción con `credit_card_status: "pending"`

### 4.2 Captura automática por email (agente nocturno)

El agente nocturno distingue dos patrones en emails de Davivienda:

| Patrón en email | Acción |
|----------------|--------|
| "Compra de $X en [comercio] con tarjeta" | Crear transacción con `payment_source: credit_card`, `credit_card_status: pending` |
| "Abono de $X a tu tarjeta desde cuenta débito" | **No crear gasto.** Ejecutar flujo de liquidación (ver 4.3) |

La distinción la resuelve el formato del email del banco, no lógica propia del sistema.

### 4.3 Flujo de liquidación (cuando llega el pago)

Cuando el sistema detecta un abono a tarjeta (email o confirmación del usuario):

1. Obtener el monto del pago (ej: $92.000).
2. Obtener las transacciones `credit_card_status: pending` ordenadas por fecha (más antigua primero).
3. Marcar como `settled` en orden FIFO hasta agotar el monto del pago.
4. Si el pago cubre todo el pendiente → todos pasan a `settled`, pool = $0.
5. Si el pago es parcial → se marcan las más antiguas hasta agotar el monto, el resto queda `pending`.
6. Registrar el abono como una transacción de tipo `credit_card_payment` (no gasto, no categoría de presupuesto) para reflejar la salida real de caja del banco.

**Nota:** El pago puede llegar días después de las compras o incluso en el siguiente mes. El `credit_card_status` persiste entre meses.

---

## 5. Impacto en presupuesto y cash flow

### Presupuesto (expense tracking)
Las transacciones `credit_card` con `credit_card_status: pending` **sí cuentan** para el presupuesto del mes en que se registraron. El usuario gastó ese dinero en ese período, independientemente de cuándo pague.

### Cash flow (liquidity projection)
El `LiquidityProjection` debe considerar el pool de crédito pendiente como una obligación futura. Si hay $200k de crédito pendiente por pagar, eso reduce el `safe_to_deploy` del período donde vence el pago.

```ruby
# En LiquidityProjection:
credit_card_pending = transactions
  .where(payment_source: 'credit_card', credit_card_status: 'pending')
  .sum(:amount)

# Este monto se suma a next_cycle_obligations si el corte cae dentro del próximo ciclo
```

---

## 6. Experiencia del usuario

### Lo que el usuario ve en el dashboard

En la zona de Detalle (Zona 3), nueva sección:

```
TARJETA DE CRÉDITO — PENDIENTE DE PAGAR
  Restaurante El Corral         30.000
  Netflix                       45.900
  Éxito                         16.100
  ─────────────────────────────────────
  Total pendiente               92.000
```

Cuando el pago llega: la sección desaparece o muestra $0.

### Lo que el agente puede decir

- "Tenés $92.000 de compras con tarjeta pendientes de pagar. El pago al banco no está registrado todavía."
- "Registré el abono de $88.000. Quedan $4.000 pendientes."
- "Recibí el abono completo. Las 3 compras de esta semana quedaron saldadas."

---

## 7. Migración de datos existentes

Las transacciones históricas no tienen `payment_source`. Se dejan como `nil` (legacy). El sistema las trata como débito para efectos de cash flow y no les aplica la lógica de crédito.

No se hace backfill retroactivo. El usuario no necesita categorizar el pasado.

---

## 8. Estado de implementación

| Componente | Estado |
|-----------|--------|
| Spec documentado | ✅ |
| Migración: `payment_source` y `credit_card_status` en transactions | ✅ |
| UI: botones de medio de pago en registro de transacción | ✅ |
| Chat agent: extracción de medio de pago en registro | ✅ |
| Agente nocturno: detección de emails de abono vs. compra | ✅ |
| Flujo de liquidación FIFO (`SettleCreditCardPayments` + `POST /transactions/settle_credit_card`) | ✅ |
| Dashboard: sección de crédito pendiente en Zona 3 | ✅ |
| LiquidityProjection: crédito pendiente incluido en `next_cycle_obligations` | ✅ |

---

## 9. Qué no se implementa en esta iteración

- Soporte para múltiples tarjetas de crédito con pools separados. El pool es único por cuenta. Si en el futuro se necesita separar por tarjeta, se agrega un campo `payment_source_label` opcional sin reescribir el modelo.
- Interés y comisiones de tarjeta. Cuando el banco agrega cargos al saldo (no compras del usuario), eso se trata como una nueva transacción categorizada en "cargas financieras". No es parte de este flujo.
- Alertas de fecha de corte. Futuro.
