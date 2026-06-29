# Finanzas — Principios de Diseño

> Estado: ⚠️ EN MIGRACIÓN A RFC-0001 — fuente de verdad del modelo OBJETIVO
> Última actualización: 2026-06-28
>
> Este spec describe el modelo de agencia de **3 tiers** (Comprometido / Necesario /
> Flexible) definido en [Rediseño.md](../producto/Rediseño.md) (RFC-0001). El código
> todavía corre el modelo anterior de 6 categorías; la migración es por etapas. Donde
> diga "objetivo" se refiere al estado post-migración, no al actualmente implementado.

> El objetivo no es llevar una contabilidad perfecta. Es cambiar conductas. La diferencia es enorme: una contabilidad te dice qué pasó, el coaching te dice qué hacer diferente.

> **Interacción**: ver [ascent-manifiesto.md](./ascent-manifiesto.md) — guía de diseño que rige cómo se siente el producto. Si hay tensión entre un flujo y el manifiesto, el manifiesto gana.

---

## Visión

Un sistema que funciona como un CFO personal en el celular. Recibe gastos en lenguaje natural por Telegram, los clasifica con inteligencia artificial, los contrasta con un plan financiero explícito, y cada noche envía un resumen con coaching personalizado basado en el comportamiento real del usuario.

A futuro: accesible a cualquier persona que quiera tomar control de sus finanzas.

---

## Principios de diseño

### Fuentes de verdad por dimensión

- flujo de caja mensual → `recurring_obligations`
- estado estructural del pasivo → `debts`
- estado estructural del activo / construcción → `investments`
- planeación futura → `planned_expenses`
- semántica conductual → `category_id` + `subcategory_id`

### 1. Categorización por agencia, no por tipo contable

El eje de clasificación del gasto no es funcional (vivienda/alimentación) ni contable, sino de **agencia**: cuánto margen real de maniobra tiene el usuario sobre cada gasto. Un sistema que agrupa "arriendo" y "pizza" bajo "Vivienda/Alimentación" no responde la pregunta que cambia decisiones: *¿qué puedo modificar si mi situación empeora?*

**Fundamento (corregido, ver `../research/categorizacion-de-gastos.md` y RFC-0001 §3):**
el eje de agencia **no** proviene de Mental Accounting (Kahneman/Thaler) — esa atribución era post-hoc. La taxonomía es una síntesis de marcos de practicantes (Conscious Spending Plan de Ramit Sethi + values-based budgeting) y se respalda en la literatura de **control percibido / locus of control y autoeficacia financiera** (Cobb-Clark et al. 2016; Asebedo 2019), que es el mecanismo que sí predice ahorro y conducta. Advertencia clave del research brief: **la taxonomía por sí sola es un lever débil**; lo que cambia conducta es la percepción de control + la reflexión en el momento de clasificar. El eje debe diseñarse como herramienta de decisión, no como taxonomía de registro.

**La regla única.** Todas las categorías responden exactamente la misma pregunta — eso es lo que las vuelve mutuamente excluyentes y estables:

> ¿Qué margen de maniobra tengo sobre este gasto si mi situación financiera empeora significativamente?

El sistema usa **3 tiers de agencia** (más `income` como entrada, no como tier de gasto):

| Tier | Código | Pregunta operativa | Pertenece aquí si |
|------|--------|--------------------|--------------------|
| **Comprometido** | `committed` | ¿Puedo dejar de pagarlo sin incumplir una obligación legal/contractual? | NO |
| **Necesario** | `necessary` | Si pierdo mis ingresos, ¿el mínimo de esta función sigue siendo > 0 (aunque reduzca el monto)? | SÍ |
| **Flexible** | `flexible` | ¿Podría llevar este gasto a cero durante una crisis sin comprometer supervivencia ni obligaciones? | SÍ |

(`discretionary` → renombrado a `flexible`.)

**Qué salió del eje y por qué:**
- **Inversión** deja de ser categoría de presupuesto. Respondía otra pregunta (¿hay retorno futuro?) y era la etiqueta más abusable vía self-licensing/motivated reasoning. Pasa a un **módulo de Patrimonio** aparte (flujo de caja vs patrimonio). El gasto "en uno mismo" (cursos, gym, suplementos) se reclasifica como `flexible` o `necessary` según la regla única.
- **Social** deja de ser categoría de agencia. Respondía por el beneficiario, no por la agencia. Sus **subcategorías** (Regalos, Salidas, Familia, Donaciones, Amigos) sobreviven y se re-parentan a su tier (`flexible`, o `necessary` para soporte familiar de subsistencia). La semántica social la lleva la subcategoría — **no se agrega un eje de tags** (las subcategorías ya existían para eso).

**Prioridad defendida (eje ortogonal).** La agencia dice *cuán cortable es*; la prioridad dice *cuánto elijo protegerlo cuando hay con qué*. Son distintas: un gasto `flexible` puede estar marcado como intocable-por-elección (ej. un tratamiento de salud que el usuario prioriza por encima de deuda y colchón). El motor de presupuesto respeta esa marca **antes** de aplicar el orden de agencia por defecto. Ver RFC-0001 §10.

Cada tier tiene subcategorías granulares (tipo funcional) que viven como metadato secundario para reportes, no como eje principal.

### 2. El plan financiero es explícito

El sistema no asume qué debería hacer el usuario con su plata. Guarda el plan en la base de datos y el agente razona en función de él. Las fases posibles:

```
debt_payoff       → Todo excedente va a deudas (snowball o avalanche)
emergency_fund    → Construcción del colchón (1-6 meses de gastos fijos)
investing         → 15%+ del ingreso a activos
wealth_building   → Diversificación, real estate, negocios
```

La transición entre fases la decide el usuario, aunque el agente puede sugerir el cambio cuando detecta que las condiciones se cumplen.

### 3. El burn rate es más útil que el total gastado

Saber que gastaste $400.000 en discrecional el 10 de abril no dice nada. Saber que al ritmo actual gastarás $1.200.000 para fin de mes, cuando el presupuesto es $500.000, cambia decisiones hoy. El sistema siempre presenta proyecciones, no solo histórico.

### 4. Sinking funds para gastos futuros conocidos

Los gastos estacionales (matrícula, impuestos, regalos de diciembre) destruyen planes financieros porque llegan "de sorpresa". El sistema permite registrarlos con anticipación y calcula la cuota mensual necesaria para llegar sin trauma.

### 5. Gamificación basada en Fogg Behavior Model

El modelo de B.J. Fogg dice que el comportamiento ocurre cuando coinciden motivación + habilidad + trigger. El sistema ya tiene el trigger (notificación nocturna). La gamificación agrega motivación extrínseca sin reemplazar la intrínseca:

- **Rachas**: días consecutivos dentro del presupuesto discrecional
- **Logros**: hitos concretos ("Primer mes sin delivery", "Deuda reducida 10%")
- **Score mensual**: 0-100 basado en adherencia al plan, no en cuánto gastó
- **Tendencias**: comparación mes a mes, no contra un ideal abstracto

---

## Modelo de datos completo

### users
```sql
id, email, name, password_digest, super_admin,
provider, uid,                          -- OAuth
created_at, updated_at
```

### categories
```sql
id, user_id (nullable — null = sistema),
name, code, category_type,              -- OBJETIVO: committed | necessary | flexible | income
                                        -- (investment → módulo Patrimonio; social → subcategorías bajo su tier; discretionary → flexible)
color, icon,
is_system,                              -- true = no se puede borrar
created_at, updated_at
```

### subcategories
```sql
id, category_id, name, code,
is_system,
created_at, updated_at
```

Subcategorías iniciales por tier (el tipo funcional es metadato secundario):

| Tier | Subcategorías |
|------|--------------|
| Comprometido | Arriendo, Créditos (pago mínimo), Seguros, Servicios públicos, Colegiaturas |
| Necesario | Mercado, Gasolina, Transporte básico, Salud, Celular |
| Flexible | Restaurantes, Delivery, Ocio, Ropa, Tecnología, Suscripciones, Cursos, Gym, Suplementos |
| Ingreso | Salario, Freelance, Reembolso, Arriendo recibido, Otros |

Notas de migración:
- Las subcategorías de la vieja **Inversión** se bifurcan: instrumentos (CDT, ETF, acciones, cripto) → módulo Patrimonio; "inversión en sí mismo" (cursos, gym, suplementos) → `flexible` (o `necessary` si el mínimo en crisis es > 0).
- **Social** (Regalos, Salidas, Familia, Donaciones, Amigos) deja de ser categoría → sus subcategorías se re-parentan al tier que corresponda (`flexible`/`necessary`); la semántica social la conserva la subcategoría, sin eje de tags.
- Aceleración de deuda (abono extra snowball/avalanche) NO es `committed` — es decisión/prioridad. Solo el pago mínimo es `committed`. Ver RFC-0001 §6.1.

### transactions
```sql
id, user_id,
date (string DD/MM),                    -- fecha en hora Colombia
concept (string),                       -- descripción libre
product (string),                       -- nequi | tc1234 | tc5678 | debito | bre-b
amount (integer),                       -- en pesos, siempre positivo
transaction_type (string),              -- expense | income
category_id, subcategory_id,
source (string),                        -- telegram | gmail | manual
status (string),                        -- confirmed | pending | projected
clarification_requested_at (datetime),
clarification_resolved_at (datetime),
metadata (jsonb),                       -- datos crudos del mensaje original
year (integer), month (integer),        -- desnormalizados para queries rápidas
created_at, updated_at
```

### budgets
```sql
id, user_id, category_id,
month (integer), year (integer),
amount_limit (integer),
created_at, updated_at
```

### debts
```sql
id, user_id,
name (string),
original_amount (integer),
current_balance (integer),
monthly_payment (integer),
interest_rate (decimal),                -- porcentaje mensual
debt_type (string),                     -- credit_card | personal_loan | family | mortgage
payoff_date (date),
status (string),                        -- active | paid_off | paused
created_at, updated_at
```

`monthly_payment` se mantiene por compatibilidad y como dato estructural de la deuda, pero la fuente de verdad del impacto mensual en caja sigue siendo `recurring_obligations`.

### recurring_obligations
```sql
id, user_id, account_id,
category_id, subcategory_id,
name, amount, due_day, active,
source_type, source_id,                 -- nullable: Debt | Investment
allocatable_type, allocatable_id,       -- legacy, compatibilidad
notes, ai_analysis,
created_at, updated_at
```

`source_type` / `source_id` permite relacionar una obligación recurrente con una entidad estructural sin volver esa entidad la fuente primaria del flujo mensual.

### planned_expenses
```sql
id, user_id, account_id,
name, amount_estimated, target_date,
planning_type, status,
category_id, subcategory_id,
notes,
created_at, updated_at
```

Fuente de verdad para gastos futuros previsibles que todavía no son transacciones reales ni obligaciones recurrentes mensuales.

### savings_goals
```sql
id, user_id,
name (string),
goal_type (string),                     -- emergency_fund | sinking_fund | investment | other
target_amount (integer),
current_amount (integer),               -- actualizado manualmente o vía transacciones
target_date (date),
monthly_contribution_needed (integer),  -- calculado: (target - current) / months_remaining
priority (integer),
status (string),                        -- active | achieved | paused
created_at, updated_at
```

### financial_contexts
```sql
id, user_id,
phase (string),                         -- debt_payoff | emergency_fund | investing | wealth_building
strategy (string),                      -- snowball | avalanche (solo aplica en debt_payoff)
monthly_surplus_target (integer),       -- cuánto quiere sobrante para metas
notes (text),                           -- el agente puede escribir observaciones
updated_at
```

### achievements
```sql
id, user_id,
code (string),                          -- identificador único del logro
name (string),
description (string),
achieved_at (datetime),
category (string),                      -- spending | saving | debt | consistency
created_at
```

### streaks
```sql
id, user_id,
streak_type (string),                   -- under_budget_discretionary | no_delivery | daily_log
current_count (integer),
best_count (integer),
last_activity_date (date),
updated_at
```

---

## Sistema de scoring mensual

El score 0-100 se calcula con esta fórmula ponderada:

| Componente | Peso | Cómo se mide |
|------------|------|-------------|
| Adherencia presupuesto flexible | 35% | gasto_real / presupuesto (invertido, menos es mejor) |
| Pagos comprometidos al día | 25% | pagos_realizados / pagos_esperados |
| Aporte a metas de ahorro | 20% | aporte_real / aporte_mensual_necesario |
| Registro completo (sin pendientes) | 10% | transacciones_confirmadas / total |
| Consistencia de registro | 10% | días_con_al_menos_1_registro / días_del_mes |

Un score de 70+ en 3 meses consecutivos activa el logro "Consistencia financiera".

---

## Integración con el agente Claude

El agente nocturno (GitHub Actions, 11pm Colombia) consume esta API en lugar de manipular el Excel. El flujo:

```
1. GET /api/v1/auth/login              → obtener token
2. GET /api/v1/transactions/pending    → resolver aclaraciones previas
3. [leer Telegram + Gmail]
4. POST /api/v1/transactions           → registrar cada gasto/ingreso
5. PATCH /api/v1/transactions/:id      → resolver pendientes encontrados
6. GET /api/v1/summary?month=&year=    → obtener resumen para coaching
7. [generar mensaje de coaching con Claude]
8. [enviar por Telegram]
```

El agente recibe el `summary` completo y tiene contexto para razonar sobre:
- Alertas de burn rate por categoría
- Progreso en metas de ahorro
- Deudas y plan de pago
- Score del mes y rachas activas

---

## Siguiente bloque prioritario

Los puntos 1-5 ya están implementados. El pendiente activo:

1. ~~dejar el wizard correcto~~ ✅
2. ~~wizard lee fuentes de verdad~~ ✅ (income_sources bloqueado, recurring bloqueado)
3. ~~conectar `planned_expenses` con `sinking_funds`~~ ✅
4. ~~matching estructural de transacciones~~ ✅ (`structural_match` en response)
5. ~~reglas cruzadas `debts` ↔ `recurring_obligations`~~ ✅
6. **Pendiente**: alinear prompts del Brain con el contrato operativo del backend (Fase E)

Spec operativo:

- [living-budget.md](./living-budget.md)

---

## Roadmap de módulos futuros

Cuando el módulo Finanzas esté estable, el mismo patrón se aplica a:

**Cuerpo**: `body_logs` (suplementos, calorías, ejercicio, sueño) — mismo dominio DDD
**Mente**: `journal_entries`, `morning_rituals`, `weekly_synthesis`
**Social**: `social_fragments`, `relationship_debriefs`, `evidence_records`

Cada módulo tiene su propio dominio en `app/domains/` y su propio conjunto de endpoints.

---

## Estado real del módulo (2026-04-28)

### Implementado y operativo

- `recurring_obligations.source_type/source_id` — relación explícita con deuda
- `planned_expenses` — CRUD completo en backend, UI y agente
- `sinking_funds` — CRUD completo; vinculables a `planned_expense_id`
- `wizard_data` — propuesta calculada desde fuentes de verdad; `suggested_sinking_funds`
- `BudgetWizardModal` — 7 pasos, income bloqueado, recurrentes bloqueados
- `structural_match` en response de `POST /transactions`
- Validación `creditos` → `Debt` requerida en `RecurringObligation`
- `POST /debts` sugiere obligación recurrente si no existe

### Pendiente

- CTAs desde wizard hacia fuente de verdad (navegar al módulo correcto al editar línea bloqueada)
- coherencia prompts del Brain con validaciones del backend (Fase E)
- soporte estructural real para `investments`

### Legacy-compatible

- `allocatable_type/allocatable_id` siguen vivos
- `source_type/source_id` es la referencia explícita preferida
- limpiar `source_*` limpia también el fallback legacy para evitar rehidratación accidental del vínculo

### Reglas operativas

- `transactions` registra hechos ya ocurridos
- `recurring_obligations` registra impacto mensual fijo en caja
- `debts` registra estado estructural del pasivo
- `planned_expenses` registra planeación futura no ejecutada

### Phase Closure Checklist

- `planned_expenses` existe en backend, UI y agente
- la relación deuda ↔ obligación es visible y operable
- el contrato entre API, UI y agente acepta unlink explícito
- el fallback legacy sigue soportado sin ser la vía preferida
