# Módulo de Presupuesto — Plan de Implementación

> Framework: Zero-Based Budgeting (ZBB) con categorías dinámicas y bolsillos
> Última actualización: 2026-04-18

---

## 1. Modelo mental: niveles de madurez financiera

La app es adaptativa. Un usuario nuevo no debería ver presupuestos ni bolsillos el primer día — eso genera abandono. El sistema detecta en qué nivel está el usuario y solo le presenta lo que corresponde a ese nivel.

### Los 6 niveles

| Nivel | Nombre | Qué puede hacer | Prerequisito |
|-------|--------|-----------------|--------------|
| 1 | **Registro** | Solo registrar transacciones. Sin presupuesto, sin perfil. | Ninguno |
| 2 | **Perfil** | Registrar ingresos y gastos recurrentes. | Haber registrado ≥10 transacciones |
| 3 | **Estrategia** | Definir fase (debt_payoff, emergency_fund, etc.) y estrategia snowball/avalanche. | Tener income_profile + recurring_obligations |
| 4 | **Presupuesto y bolsillos** | Crear plan mensual ZBB con categorías dinámicas y sinking funds. | Tener estrategia definida |
| 5 | **Inversión** | Presupuesto orientado a crecimiento de patrimonio, sin deudas. | Phase = investing o wealth_building |
| 6 | **Patrimonio** | Conceptos complejos: portafolio, diversificación, proyecciones. | Historial de >12 meses en nivel 5 |

### Cómo el sistema detecta el nivel actual

```
nivel_actual =
  si no hay income_sources activos              → Nivel 1
  si no hay financial_context.phase             → Nivel 2
  si phase es null o strategy es null           → Nivel 3
  si no hay monthly_financial_plan confirmado   → Nivel 4
  si phase es investing o wealth_building       → Nivel 5
  si nivel 5 por >12 meses                     → Nivel 6
```

El `CompletenessIndicator` actual ya maneja parcialmente esto con `dependsOn`. La lógica de niveles lo formaliza.

### Qué NO cambia con los niveles

El agente siempre puede registrar transacciones independientemente del nivel. Los niveles solo determinan qué features del UI se muestran y qué wizards están disponibles.

---

## 2. Marco conceptual: ZBB con categorías dinámicas

**Zero-Based Budgeting:** cada mes, cada peso del ingreso tiene un destino asignado. El resultado es siempre `ingreso - todo lo asignado = 0`. No hay dinero flotando.

**Por qué las categorías deben ser dinámicas:**
- No todos tienen arriendo (algunos viven con familia)
- No todos tienen moto ni carro
- No todos comen en casa
- Un usuario con moto de 350cc tiene gastos de mantenimiento que otro no tiene
- Las apps que imponen categorías fijas crean fricciones y abandono

**La solución:** el sistema propone categorías basadas en el historial real de transacciones del usuario. El usuario confirma, ajusta o agrega las suyas. No hay categorías que no reconozca como propias.

---

## 3. Categorías: sistema + dinámicas + bolsillos

### 3.1 Categorías del sistema (base, no eliminables)

Solo 3 categorías son absolutamente invariantes porque toda persona tiene estos gastos:

| Código | Nombre | Tipo ZBB |
|--------|--------|----------|
| `debt_payoff` | Pago de deudas | Committed (solo si hay deudas activas) |
| `savings_emergency` | Fondo de emergencia | Committed (solo en fase emergency_fund+) |
| `income` | Ingresos | — (no es un gasto) |

El resto son **sugeridas** pero no obligatorias. El sistema las propone basándose en el historial.

### 3.2 Categorías sugeridas (propuestas por el agente según historial)

El agente detecta patrones en las transacciones de los últimos 3 meses y propone las categorías que tienen actividad real:

| Código sugerido | Proponer si... |
|-----------------|----------------|
| `housing` | Hay transacciones de arriendo o servicios del hogar |
| `utilities` | Hay pagos de internet, celular, servicios públicos |
| `groceries` | Hay compras en supermercados o tiendas |
| `dining_out` | Hay transacciones en restaurantes o deliveries |
| `transportation` | Hay gasolina, Uber, bus, peajes |
| `vehicle_maintenance` | Hay mantenimientos detectados |
| `health` | Hay gastos médicos o farmacia |
| `personal_care` | Hay gimnasio, barbería, estética |
| `entertainment` | Hay streaming, eventos, salidas |
| `education` | Hay cursos, libros, suscripciones educativas |

Si no hay historial (usuario nuevo): el agente pregunta directamente cuáles aplican.

### 3.3 Categorías custom del usuario

El usuario puede crear categorías con nombre libre. Ejemplo: "Regalos familia", "Proyecto moto", "Fondo viaje". Estas son presupuestadas como cualquier categoría estándar.

### 3.4 Bolsillos (Sinking Funds)

Un bolsillo es una categoría especial para gastos irregulares pero predecibles. La diferencia con una categoría normal:

- **Categoría normal:** se presupuesta y gasta cada mes. Si no se gasta, el saldo no pasa al siguiente mes.
- **Bolsillo:** se contribuye mensualmente y el saldo **acumula** hasta que llega el gasto. Es como un ahorro con propósito.

**Ejemplos de bolsillos:**

| Bolsillo | Contribución mensual | Lógica |
|----------|---------------------|--------|
| SOAT moto | $35.000/mes | SOAT anual ~$420.000 → dividido entre 12 |
| Tecnomecánica | $25.000/mes | Cada 2 años ~$600.000 → dividido entre 24 |
| Mantenimiento moto | $80.000/mes | Cada 1000 km, ~$240.000 → según frecuencia estimada |
| Ropa / temporada | $50.000/mes | Compra estacional 2x año |
| Regalos / fechas | $30.000/mes | Navidad, cumpleaños, etc. |
| Vacaciones | $100.000/mes | Meta anual definida por usuario |

**Modelo de datos de un bolsillo:**
```
sinking_fund:
  name:                "SOAT moto"
  monthly_contribution: 35_000
  target_amount:        420_000      # monto del gasto cuando llegue
  target_date:          2027-01-01   # fecha estimada del gasto
  current_balance:      0            # se acumula cada mes
  account_id, user_id
```

**Cómo entra al presupuesto mensual:**
La contribución mensual del bolsillo (`monthly_contribution`) entra en el plan como un gasto más — sale del margen libre. Cuando llega el gasto real, se descuenta del `current_balance` del bolsillo, no del presupuesto del mes.

**Cómo lo propone el agente:**
"Tenés una moto Yamaha 350. En Colombia el SOAT promedio para motos de esta cilindrada es ~$420.000 anuales. Si apartás $35.000 cada mes, llegás al año sin sentirlo. ¿Querés crear un bolsillo para el SOAT?"

### Relación con `planned_expenses`

`planned_expenses` y `sinking_funds` no son lo mismo:

- `planned_expenses` lista el gasto futuro previsto y su estado
- `sinking_funds` modela la reserva acumulativa usada para fondearlo

Puede existir un `planned_expense` sin bolsillo asociado todavía. En esta fase no hay sincronización automática entre ambas entidades.

---

## 4. Flujo conversacional de creación del presupuesto (Nivel 4)

El agente NO presenta un formulario estático. El flujo es una conversación guiada en el UI web:

### Paso 1 — Análisis silencioso

El agente recibe el `budget_context` (Fase 1 ya implementada) y analiza:
- Historial de transacciones de los últimos 3 meses por categoría
- Recurring obligations registrados
- Bolsillos existentes
- Monto promedio real gastado por categoría

### Paso 2 — Propuesta de categorías

```
"Basándome en tus últimos 3 meses, veo que gastás regularmente en estas áreas:

  ✓ Vivienda (arriendo $2.500.000)
  ✓ Servicios (celular, internet, suscripciones ~$230.000)
  ✓ Mercado (~$380.000 promedio)
  ✓ Transporte (gasolina ~$120.000)
  ✓ Comida por fuera (~$95.000)

¿Querés agregar alguna categoría que falte, o quitar alguna que no aplique?"
```

### Paso 3 — Ajuste de categorías

El usuario puede:
- Confirmar la lista tal cual
- Agregar categorías custom
- Quitar categorías que no apliquen
- El agente muestra un listado seleccionable (UI: lista con checkboxes o chips)

### Paso 4 — Propuesta de montos

Con las categorías confirmadas, el agente propone montos basados en el historial real:

```
"Aquí está mi propuesta para cada categoría, basada en lo que 
 realmente gastaste los últimos 3 meses:

  Vivienda:         $2.500.000  (fijo, viene del arriendo)
  Servicios:        $  230.716  (fijo, suscripciones)
  Mercado:          $  380.000  (promedio 3 meses: $352k, $401k, $387k)
  Transporte:       $  150.000  (promedio: $118k, ajusté con margen)
  Comida por fuera: $  100.000  (promedio: $95k)
  Mínimos deuda:    $1.696.433  (fijo)
  Abono snowball:   $  794.851  (excedente después de todo)
  ─────────────────────────────
  Total:            $5.851.000  de $6.480.000 base
  Sin asignar:      $  629.000  ← ¿a dónde va esto?

¿Querés modificar algún monto, o asignar lo que queda?"
```

### Paso 5 — Ajuste de montos

El usuario selecciona qué categoría quiere modificar. El agente pregunta el nuevo monto y recalcula el excedente en tiempo real.

### Paso 6 — Bolsillos (opcional)

```
"Noté que tenés una moto. ¿Querés crear bolsillos para gastos 
 anuales como SOAT, tecno-mecánica o mantenimientos?
 
 Sugerencia: $140.000/mes apartados en 3 bolsillos cubrirían
 todos los gastos anuales de la moto sin sorpresas."
```

### Paso 7 — Confirmación

El agente presenta el resumen final del plan ZBB completo con todas las categorías y bolsillos. El usuario confirma o vuelve a ajustar.

---

## 5. Qué pasa con usuarios nuevos (sin historial)

Sin transacciones previas, el agente no puede inferir patrones. El flujo es diferente:

**Paso 1:** El agente pregunta directamente cuáles categorías aplican (lista de selección).

**Paso 2:** Para cada categoría seleccionada, pregunta el monto estimado. Si el usuario no sabe, el agente sugiere rangos según contexto colombiano:
- "¿Cuánto pagás de arriendo? En Colombia el promedio para estratos 3-4 en ciudad principal es $1.200.000 - $2.500.000."
- "¿Cuánto gastás en mercado? El promedio para una persona sola es $350.000 - $500.000/mes."

**Paso 3:** El plan se marca como `provisional` y se sugiere revisarlo después del primer mes con datos reales.

---

## 6. Impacto en la arquitectura técnica

### 6.1 Nuevas tablas necesarias

```ruby
# sinking_funds — bolsillos de ahorro con propósito
create_table :sinking_funds do |t|
  t.references :user,    null: false
  t.references :account, null: true
  t.string  :name,                    null: false
  t.integer :monthly_contribution,    null: false, default: 0
  t.integer :target_amount,           null: true   # nil = sin meta fija
  t.date    :target_date,             null: true   # nil = recurrente indefinido
  t.integer :current_balance,         null: false, default: 0
  t.string  :category,               null: false  # a qué categoría pertenece
  t.boolean :active,                  null: false, default: true
  t.text    :notes
  t.timestamps
end

# budget_categories — categorías dinámicas por cuenta
create_table :budget_categories do |t|
  t.references :account, null: false
  t.string  :code,        null: false   # slug único por account
  t.string  :name,        null: false   # nombre display
  t.string  :category_type, null: false # committed | necessary | discretionary | investment
  t.boolean :system,      null: false, default: false  # true = no eliminable
  t.boolean :active,      null: false, default: true
  t.integer :sort_order,  null: false, default: 0
  t.timestamps
end

add_index :budget_categories, [:account_id, :code], unique: true
```

### 6.2 Cambios en el motor de cálculo

El `BudgetCalculator` de la Fase 2 original (distribución fija del margen libre) ya **no aplica**. En su lugar:

- Rails calcula el **piso comprometido** (obligaciones fijas + mínimos de deuda + contribuciones a bolsillos)
- El **margen libre** se pasa al agente sin distribuir
- El agente distribuye el margen conversacionalmente con el usuario
- El agente usa el historial real de transacciones para proponer montos por categoría

### 6.3 Cambios en budget_context

El endpoint `GET /api/v1/budget_context` debe incluir también:
- Historial de gasto promedio por categoría (últimos 3 meses)
- Bolsillos activos con `current_balance`
- Categorías dinámicas de la cuenta

### 6.4 El monthly_financial_plan guarda el resultado final

Al confirmar, el plan guarda:
- `base_budget_income`, `recurring_obligations_total`, `debt_minimums_total` (como ahora)
- `category_allocations: jsonb` — distribución acordada por categoría `{ housing: 2500000, groceries: 380000, ... }`
- `sinking_fund_contributions: jsonb` — contribuciones acordadas a bolsillos ese mes

---

## 7. Revisión de las fases de implementación

### Nota de ejecución 2026-04-23

Este documento sigue describiendo bien el modelo de presupuesto, pero la siguiente ejecución ya no debe arrancar por "más categorías dinámicas". La prioridad práctica cambió:

- primero dejar el wizard correcto frente a las fuentes de verdad ya existentes
- luego conectar `planned_expenses` con `sinking_funds`
- luego agregar matching estructural de transacciones

Plan operativo actual:

- [phase-3-4-living-budget-integration.md](./phase-3-4-living-budget-integration.md)

### Fase 1 — Cimientos ✅ COMPLETADA
Migraciones + `budget_category` en obligations + `actionable` polimórfico + `GET /api/v1/budget_context`

### Fase 2 — Categorías dinámicas y bolsillos (PRÓXIMA)
- Migración: `sinking_funds` + `budget_categories`
- Seed: categorías del sistema pre-cargadas por cuenta nueva
- Endpoint: `GET /api/v1/budget_context` extendido con historial por categoría y bolsillos
- El motor de cálculo solo calcula el piso comprometido — no distribuye el margen

### Fase 3 — Integración agente conversacional
- `WebChatJob` pre-fetches `budget_context` extendido
- Prompt del agente con flujo conversacional de 7 pasos
- Eventos UI: `show_category_selector`, `show_amount_editor`, `show_plan_proposal`
- El agente usa historial real para proponer montos por categoría

### Fase 4 — Confirmación + IonModal UI
- Persistencia del plan con `category_allocations` y `sinking_fund_contributions`
- Card rediseñada como `IonModal` siguiendo el estilo de la app
- Desglose completo por categoría en el modal de confirmación

### Fase 5 — Tracking mensual (futuro)
- Comparativa categoría vs gasto real del mes
- Alertas cuando una categoría supera el límite
- Rollover automático mes a mes

### Ajustes funcionales ya decididos para la siguiente ejecución

- El paso de ingresos del wizard no debe duplicar información ya definida en `income_sources`
- Las líneas fijas como arriendo, cuotas y suscripciones no se editan desde el wizard; se muestran bloqueadas y remiten a `recurring_obligations`
- Los `planned_expenses` obligatorios deben entrar al plan como necesidad de fondeo, no como campo opcional aislado
- Cada `planned_expense` relevante debe poder traducirse a su propio bolsillo
- La capa de resumen final debe explicar qué viene de fuente fija, qué es sugerencia histórica y qué es editable

---

## 8. Pendientes UI

### 8.1 La card del agente no sigue el estilo de la aplicación

**Problema:** `AgentEventRenderer` usa card flotante con colores hardcodeados en lugar de `IonModal` y CSS variables del sistema de diseño.

**Patrón correcto:** `IonModal` con `IonHeader` + `IonToolbar` + `IonTitle` + `IonButtons`. CSS con `var(--color-*)`, `var(--text-*)`. Ver `IncomeSetupWizard` como referencia.

**Cambios necesarios:**
- `PlanProposalCard` → `IonModal` (bottom sheet mobile, centrado desktop `max-width: 480px`)
- Reemplazar colores hardcodeados por CSS variables
- Botones usando componente `Button` de la app
- Header: eyebrow + título + botón cerrar en `IonButtons slot="end"`

---

## 9. Lo que NO se construye todavía

- Envelope tracking en tiempo real — Fase 5
- Budget rollover automático mes a mes — Fase 5
- Notificaciones de límite de categoría — Fase 5
- Comparativa mes a mes — Fase 5
- Soporte aguinaldo / bonos estacionales — Fase 5
- Portafolio de inversiones — Nivel 6, futuro lejano
