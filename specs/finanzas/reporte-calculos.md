# Reporte detallado de cálculos del negocio

> Estado: 🔍 auditoría — generado 2026-06-24
> Propósito: inventario riguroso de TODA fórmula de negocio en el sistema, con su
> ubicación exacta, inputs, respaldo bibliográfico y banderas de inconsistencia.
> Bibliografía de referencia: `specs/research/metodologias-coaching-financiero.md`
> (CFP 28/36, YNAB, Ramit Sethi CSP, Dave Ramsey).
>
> Convención de banderas:
> - 🟢 Correcto y con respaldo bibliográfico.
> - 🟡 Heurístico / decisión de producto (sin bibliografía estricta, pero defendible).
> - 🟠 Divergencia con la bibliografía o con otra parte del sistema (revisar).
> - 🔴 Posible bug / supuesto frágil que puede producir un número equivocado.

---

## 1. Saldo y liquidez

### 1.1 Saldo confirmado (`confirmed_balance`)
- **Dónde:** `TransactionRepository#confirmed_balance(account_id:)` → consumido por `SummaryController` y `TransactionsController#balance`.
- **Fórmula:**
  ```
  confirmed_balance = Σ (income_confirmed − expense_confirmed)
                      SOLO sobre meses que tienen ≥1 gasto confirmado
  ```
- **Inputs:** todas las transacciones confirmadas de la cuenta, agrupadas por (año, mes, tipo).
- **Respaldo:** 🟡 definición propia. La regla "excluir meses solo-ingreso" no es estándar contable — es una decisión para no inflar el saldo con ingresos viejos previos al inicio del tracking (heredada del seed de la migración `20260603121042`).
- **Banderas:**
  - 🟠 La regla "excluir meses solo-ingreso" puede confundir: un mes con ingreso pero sin gasto aún registrado no cuenta hasta que llegue el primer gasto. Documentar como decisión explícita.
  - ✅ Antes dependía de una columna-cache (`accounts.confirmed_balance`) que se desincronizó y produjo un margen libre falso de −$4M (2026-06-24). La columna fue eliminada; ahora el cálculo deriva de transacciones (fuente de verdad). Ver [[project_funds_and_debt_model]].

### 1.2 Margen libre (`commitment_gap`)
- **Dónde:** `CashFlowRunway#call`.
- **Fórmula:**
  ```
  commitment_gap = confirmed_balance
                 − committed_before_next_income
                 − (daily_necessary_burn × days_to_next_income)
  committed_before_next_income = Σ remaining de obligaciones con due_day ∈ [hoy, próximo_ingreso]
  remaining = max(amount − pagado_este_ciclo, 0)
  ```
- **Respaldo:** 🟡 modelo propio de liquidez de corto plazo (no es un ratio bibliográfico, pero es coherente: "¿me alcanza hasta el próximo ingreso?"). Es el guardrail universal del agente.
- **Banderas:**
  - 🟠 La ventana de obligaciones es estricta `due_day ∈ [hoy, próximo_ingreso]`. Las obligaciones con `due_day` ya pasado este mes pero **no pagadas** NO se cuentan (se asume pagadas). Si el usuario no pagó algo vencido, el margen se sobreestima.
  - 🟡 Si no hay próximo ingreso en el mes, cae a fin de mes (`Date.new(y,m,-1)`); puede dar ventanas raras a fin de mes.

### 1.3 Tu ritmo (`daily_necessary_burn`)
- **Dónde:** `CashFlowRunway#compute_daily_burn`.
- **Fórmula:**
  ```
  daily_burn = Σ(gastos 'necessary' confirmados últimos 30 días) / 30
  si historial < 14 días → fallback 30.000 COP/día
  ```
- **Respaldo:** 🟡 heurístico. La ventana de 30 días y el `MIN_HISTORY_DAYS=14` son razonables pero arbitrarios.
- **Banderas:**
  - 🔴 El fallback de **30.000 COP/día** es un número mágico que, en cuentas nuevas, define el margen libre y el `health_status`. Para un usuario con gasto real muy distinto, distorsiona el diagnóstico. Considerar derivarlo del plan en vez de constante.
  - 🟡 Divide siempre entre 30 aunque la ventana real sea menor → subestima el burn diario en cuentas con pocos días de datos.

### 1.4 Días de colchón (`buffer_days`) y estado (`health_status`)
- **Dónde:** `CashFlowRunway`.
- **Fórmula:**
  ```
  effective_runway_days = (confirmed_balance − committed) / daily_burn   (floor)
  buffer_days           = effective_runway_days − days_to_next_income
  health_status: critical si confirmed_balance ≤ 0 o commitment_gap < 0
                 warning  si buffer_days < 2
                 comfortable en otro caso
  ```
- **Respaldo:** 🟡 umbral `COMFORTABLE_BUFFER_DAYS = 2` es de producto.
- **Banderas:** 🟢 lógica consistente; depende de inputs 1.1–1.3.

---

## 2. Ratios de salud financiera (`HealthMetrics`)

> Estos SÍ tienen respaldo bibliográfico directo (CFP/YNAB/Sethi). Denominador =
> `base_budget_income` del plan activo; si no hay plan, los ratios son `nil`.

### 2.1 Carga de gastos fijos (`ratio_gastos_fijos`)
- **Fórmula:** `Σ obligaciones_activas / base_income × 100`.
- **Umbrales código:** excelente ≤50% · sano 51-65% · warning 66-75% · crítico >75%.
- **Respaldo:** 🟢 coincide con la metodología (`≤50% excelente`). Incluye mínimos de deuda como gasto fijo (decisión documentada).

### 2.2 Fondo de emergencia (`emergency_fund.months_covered`)
- **Fórmula:**
  ```
  bare_bones = Σ TODAS las obligaciones activas (incluye mínimos de deuda)
  months_covered = ef_balance / bare_bones
  ef_balance = SavingsGoal con nombre ~ /emergencia|emergency/i  (current_amount)
  ```
- **Umbrales código:** none <0.5m · starter <1m · minimal <3m · healthy <6m · excellent ≥6m.
- **Respaldo:** 🟢 (3-6 meses es el estándar universal).
- **Banderas:**
  - 🟠 "bare-bones" clásico EXCLUYE deuda no esencial; aquí se INCLUYEN los mínimos de deuda. Es una decisión documentada (en Colombia no pagar reporta a DataCrédito), pero **sube el target** vs. el bare-bones clásico. Dejar explícito.
  - 🟠 `ef_balance` se detecta por nombre del SavingsGoal (regex). Si el usuario renombra la meta, deja de contar.

### 2.3 Tasa de ahorro (`tasa_ahorro`)
- **Fórmula:** `Σ monthly_contribution de metas activas / base_income × 100`.
- **Umbrales código:** insuficiente <5% · básico 5-10% · sano 10-15% · excelente >15%.
- **Respaldo:** 🟠 **DIVERGENCIA.** La metodología (`specs/research/...:259-260`) define `15-20% bueno`, `>20% excelente`. El código marca "excelente" desde **>15%** — es más laxo. Alinear umbrales o justificar la diferencia.
- **Banderas:** 🟠 mide ahorro *planeado* (monthly_contribution de metas), no *ejecutado*. Un usuario con metas ambiciosas que no aporta mostraría buena tasa.

### 2.4 DTI — Debt-to-Income (`dti`)
- **Fórmula:** `Σ monthly_payment de deudas activas / base_income × 100`.
- **Umbrales código:** safe ≤20% · warning 21-35% · stress >35%.
- **Respaldo:** 🟠 umbrales 🟢 (coinciden con back-end DTI de la regla 28/36), pero el **denominador diverge**: la regla 28/36 usa ingreso **bruto**; el código usa `base_income` (base del plan, ≈ neto). Es deliberado ("mide estrés real de caja") pero hace los % NO comparables con el estándar 28/36. Documentar.

### 2.5 Edad del dinero (`age_of_money`)
- **Fórmula:** FIFO simplificado — para cada uno de los últimos 10 egresos, días hasta el ingreso confirmado más reciente anterior; promedio.
- **Umbrales código:** paycheck_to_paycheck <14d · improving 14-30d · healthy ≥30d.
- **Respaldo:** 🟢 concepto YNAB (Regla 4). Umbral 30d correcto.
- **Banderas:** 🟡 aproximación (no es FIFO real por lotes de dinero). Requiere ≥3 egresos y ≥1 ingreso o devuelve `nil`.

### 2.6 Prioridad del excedente (`coaching_priority`)
- **Fórmula (secuencia):** fondo <1 mes → `emergency_fund_starter` · hay deuda → `debt_payoff` · fondo <3 meses → `complete_emergency_fund` · resto → `invest`.
- **Respaldo:** 🟢 secuencia universal (colchón mínimo → deuda → colchón completo → invertir). Fuente única de verdad para el agente.

---

## 3. Presupuesto y ejecución del mes

### 3.1 Proyección de gasto (`BurnRateCalculator`)
- **Fórmula:** `projected = gastado / días_transcurridos × días_del_mes` (proyección lineal). `pct = projected / budget`.
- **Comportamiento por categoría:** `variable_linear`, `fixed_once`, `fixed_recurring`, `savings_goal`, `debt_payment`, `variable_spiky` (clasificado por tipo + regex de nombre).
- **Respaldo:** 🟡 proyección lineal es estándar simple.
- **Banderas:**
  - 🟡 `variable_linear` marca warning si `ratio ≥ progreso_temporal + 0.2` — el **+0.2 (20%) es arbitrario** (sin bibliografía).
  - 🟡 La clasificación por regex de nombre es frágil (depende de cómo nombró el usuario la categoría).

### 3.2 Ejecución de ingresos / obligaciones (`SummaryController#build_*_execution`)
- **Fórmula:** por fuente/obligación: `delivered = min(realized, expected)`, `remaining = max(expected − delivered, 0)`, `pct = delivered/expected`. `status`: covered/partial/pending/unplanned.
- **Respaldo:** 🟢 contabilidad directa, sin supuestos.

### 3.3 Excedente del mes (`overflow_status`, `realized_overflow`)
- **Dónde:** `SummaryController#build_overflow_status`.
- **Fórmula:**
  ```
  realized_overflow = max(confirmed_income − base_budget_income − realized_expected_variable_income, 0)
  ```
- **Respaldo:** 🟡 modelo propio (ingreso por encima de la base del plan = excedente disponible).
- **Banderas:** 🟢 consistente con el plan.

---

## 4. Plan mensual

### 4.1 Generación del plan (`GenerateMonthlyFinancialPlan`)
- **Fórmulas:**
  ```
  planning_income (modo expected) = base + Σ(variable × reliability_score/100)
  planning_income (conservative)  = base
  protected_buffer  = round_1000(planning_income × 0.05)
  available_after_fixed = max(planning_income − recurring − debt_minimums − buffer, 0)
  discretionary_limit = min(round_1000(planning_income × disc_rate), available_after_fixed)
  disc_rate por fase: debt_payoff 15% · emergency_fund 20% · investing 25% · wealth_building 30%
  rolling: hereda valor previo si |cambio| ≤ 10%, si no recalcula
  ```
- **Respaldo:** 🟡 las tasas (5% buffer, 15/20/25/30%, 10% rolling) son **decisiones de producto** inspiradas en CFP/Sethi, no fórmulas bibliográficas exactas.
- **Banderas:**
  - 🟡 Ponderar ingreso variable por `reliability_score` es razonable pero el score por defecto (50) es un supuesto fuerte.
  - 🟡 Umbral rolling 10% arbitrario.

### 4.2 Propuesta de presupuesto (`ProposeBudget`)
- **Fórmulas:**
  ```
  free_margin = planning_income − (obligaciones + deuda_min + sinking + aporte_meta)
  surplus_target = (solo debt_payoff/emergency_fund y reward_pct>0) round_1000(min(income × reward_pct/100, free_margin))
  effective_margin = max(free_margin − surplus_target, 0)
  con historial: sugerido = overspent ? last_budgeted : promedio_mensual; escala ↓ si Σ > free_margin
  sin historial: COLOMBIAN_RANGES hardcoded (rangos por categoría)
  ```
- **Patrones (últimos 3 planes cerrados):**
  ```
  consistently_over: variance_pct > 15% en ≥2 meses
  income_overestimated: income_actual < 95% × base en ≥2 meses
  ```
- **Respaldo:** 🟡 heurístico.
- **Banderas:**
  - 🟡 `COLOMBIAN_RANGES` son estimaciones hardcoded (estrato 3-4, 1 persona) — no aplican a todos los perfiles.
  - 🟡 Umbrales de patrones (15%, 95%, 2 meses) arbitrarios.

### 4.3 Cierre de mes (`CloseMonthlyPlan`)
- **Fórmulas:**
  ```
  income_actual / expense_actual = Σ confirmados del mes
  overflow_amount = max(income_actual − expense_actual − recurring_total − debt_minimums_total − buffer, 0)
  por categoría: variance = actual − budgeted; variance_pct = variance/budgeted × 100
  ```
- **Banderas:**
  - 🔴 **Posible doble-resta en `overflow_amount`:** `expense_actual` ya incluye los pagos de obligaciones y deuda (son gastos confirmados); restar además `recurring_total` y `debt_minimums_total` los descuenta dos veces → subestima el excedente, y ese excedente alimenta el `carryover` del siguiente plan. Revisar la intención.

---

## 5. Deuda

### 5.1 Interés mensual (`ApplyMonthlyInterest`)
- **Fórmula:** `interés = ceil(current_balance × interest_rate / 100)`, una vez por mes (idempotente por `interest_last_applied_on`).
- **Banderas:**
  - 🔴 **Semántica de `interest_rate` sin verificar.** Se aplica como tasa **mensual** sobre el saldo. Si el valor se captura/guarda como tasa **anual** (E.A., lo habitual en Colombia), se sobrecobra ~12×. Confirmar cómo se ingresa `interest_rate` y normalizar (E.A. → mensual = `(1+EA)^(1/12) − 1`).
  - 🟡 Es interés simple sobre saldo decreciente, no una tabla de amortización (aceptable como aproximación, pero documentarlo).

### 5.2 Saldo de deuda / liquidación
- **Dónde:** `CreateTransaction#apply_debt_payment` + modelo `Debt` (`auto_paid_off`, `deactivate_obligation_if_resolved`).
- **Fórmula:** `nuevo_saldo = max(saldo − monto_pago, 0)`; al llegar a 0 → `paid_off` + desactiva la obligación recurrente. Tarjetas de crédito excluidas del auto-descuento (saldo rotativo).
- **Respaldo:** 🟢 directo. Ver [[project_funds_and_debt_model]].
- **Banderas:** 🟡 reduce el saldo por el monto del pago completo (no separa capital vs. interés del pago).

---

## 6. Otros cálculos

### 6.1 Matching de transacciones (`DetectTransactionStructure`)
- **Fórmula:** score por coincidencia de concepto + monto + subcategoría + día → confianza `high|medium|low`. Solo `high` se auto-vincula.
- **Respaldo:** 🟡 heurístico de scoring. 🟢 política conservadora (solo high auto-vincula).

### 6.2 Gamificación (`ComputeXP`) — fuera del núcleo financiero
- XP por eventos (transacción confirmada, mes cerrado, etc.). No afecta cifras financieras del usuario; en rediseño. Ver [[project_coach_direction]].

---

## 7. Hallazgos prioritarios (resumen accionable)

| # | Cálculo | Severidad | Hallazgo |
|---|---------|-----------|----------|
| 1 | `ApplyMonthlyInterest` | 🔴 | `interest_rate` se asume mensual; si es E.A. se sobrecobra ~12×. Verificar y normalizar. |
| 2 | `CloseMonthlyPlan.overflow_amount` | 🔴 | Posible doble-resta de obligaciones/deuda (ya incluidas en `expense_actual`). Afecta el carryover. |
| 3 | `CashFlowRunway` fallback burn 30k | 🔴 | Número mágico que define salud en cuentas nuevas; derivar del plan. |
| 4 | `tasa_ahorro` umbrales | 🟠 | Código "excelente >15%" vs. metodología ">20%". Alinear. |
| 5 | `dti` denominador | 🟠 | Usa ingreso base, no bruto (regla 28/36). % no comparables con el estándar. Documentar. |
| 6 | `emergency_fund` bare-bones | 🟠 | Incluye mínimos de deuda (sube el target vs. bare-bones clásico). Decisión, documentar. |
| 7 | Definiciones de saldo múltiples | 🟠 | `SummaryController` (acumulado) vs. `BuildNightMetrics#compute_balance` (mes + mes previo) no concuerdan. Unificar en `TransactionRepository#confirmed_balance`. |
| 8 | `confirmed_balance` excluye meses solo-ingreso | 🟠 | Regla no estándar; documentar para que el usuario entienda. |
| 9 | Umbrales/tasas de plan y presupuesto | 🟡 | 5% buffer, 15/20/25/30% discrecional, 10% rolling, 15%/95% patrones, +0.2 burn: heurísticas de producto sin bibliografía estricta. Aceptables, pero deberían quedar declaradas como tales. |
| 10 | `emergency_fund` / detección por nombre | 🟠 | Se detecta el fondo por regex en el nombre del SavingsGoal; renombrarlo lo rompe. |

> Próximo paso sugerido: atacar 🔴 (1-3) primero — son los que pueden producir cifras
> objetivamente equivocadas. Luego alinear 🟠 (4-8) con la bibliografía/entre sí.
