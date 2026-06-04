# Mejoras de Fundamentos Financieros

> Iniciado: 2026-06-03
> Origen: auditoría contra metodologías de coaching financiero (ver `specs/research/metodologias-coaching-financiero.md`)
> Criterio de priorización: impacto en calidad del coaching del agente × costo de implementación

---

## Estado general

| # | Mejora | Área | Costo | Estado |
|---|--------|------|-------|--------|
| 1 | Separar emergency_fund del balance libre en runway/safe_to_deploy | API | Bajo | ✅ 2026-06-03 |
| 2 | Ratio de gastos fijos como métrica de diagnóstico | API | Bajo | ✅ 2026-06-03 |
| 3 | Cobertura fondo de emergencia en meses (bare-bones) | API | Bajo | ✅ 2026-06-03 |
| 4 | `discretionary_limit` dinámico por fase financiera | API | Medio | ⏳ Pendiente |
| 5 | Tasa de ahorro mensual como % del ingreso | API | Bajo | ✅ 2026-06-03 |
| 6 | DTI (debt-to-income ratio) calculado | API | Medio | ✅ 2026-06-03 |
| 7 | Age of Money (días promedio ingreso→gasto) | API | Medio | ✅ 2026-06-03 |
| 8 | Refactor `summary_controller` → interactores con tests | API | Alto | ⏳ Pendiente |
| 9 | Prompt nocturno: fase de reconciliación de pagos anticipados | Agente | Nulo | ✅ 2026-06-03 |
| 10 | Migración `covers_period_month/year` en transactions | API+DB | Medio | ⏳ Pendiente |

---

## Detalle por mejora

### #1 — Separar emergency_fund del balance libre
**Problema:** `CashFlowRunway` y `safe_to_deploy` incluyen el saldo del fondo de emergencia como capital disponible. Si el usuario tiene $3M en cuenta y $2M son fondo de emergencia, el agente ve $3M disponibles.
**Solución:** Leer `savings_goals` con `goal_type = emergency_fund` y restar `current_amount` del balance operativo antes de calcular runway.
**Impacto:** El agente no recomienda gastar dinero intocable.

### #2 — Ratio de gastos fijos
**Problema:** No existe como métrica expuesta. El agente no puede distinguir "problema de disciplina" vs "problema de estructura".
**Solución:** `ratio_fijos = recurring_obligations_sum / base_budget_income`. Exponer en el endpoint de health/summary.
**Rangos:** ≤50% excelente | 51-65% saludable | 66-75% alerta | >75% crítico.

### #3 — Cobertura fondo de emergencia en meses
**Problema:** Solo existe como monto absoluto. El agente no sabe si el usuario tiene 0, 1 o 6 meses cubiertos.
**Solución:** `meses_cobertura = saldo_fondo_emergencia / gastos_esenciales_mensuales`. Bare-bones = recurring_obligations (excluye deuda) como proxy inicial.
**Impacto:** El agente puede decir "tienes 1.2 meses — la prioridad es llegar a 3".

### #4 — Discretionary limit dinámico por fase
**Problema:** Fijo en 10% del ingreso. Ramsey/Sethi/CFP recomiendan 20-35% para fases post-deuda.
**Solución:** Tabla de límites por `financial_context.phase`:
- `debt_payoff`: 10-15% (restrictivo, prioridad deuda)
- `emergency_fund`: 15-20%
- `investing`: 20-30%
- `wealth_building`: 25-35%

### #5 — Tasa de ahorro mensual
**Problema:** Solo montos absolutos. El agente no puede decir "estás ahorrando 8%, la meta es 15%".
**Solución:** `tasa_ahorro = sum(savings_goals.monthly_contribution) / base_budget_income * 100`.
**Benchmarks:** <5% insuficiente | 5-10% básico | 10-15% saludable | >15% bueno.

### #6 — DTI (Debt-to-Income Ratio)
**Problema:** No existe. El agente no puede diagnosticar si la carga de deuda es sostenible.
**Solución:** `dti = sum(debt.monthly_payment) / base_budget_income * 100`.
**Umbrales LatAm (sin hipoteca):** ≤20% seguro | 21-35% advertencia | >35% estrés.

### #7 — Age of Money
**Problema:** No implementado. Es la métrica norte de YNAB — mide si el usuario está rompiendo el ciclo paycheck-to-paycheck.
**Solución:** Promedio de (fecha_gasto - fecha_ingreso) para las últimas 10 transacciones de egreso.
**Target:** ≥30 días = gastando dinero del ciclo anterior.

### #8 — Refactor summary_controller
**Problema:** 783 líneas de lógica financiera inline sin tests propios. `safe_to_deploy` no tiene fuente única de verdad.
**Solución:** Extraer a interactores: `HealthMetrics`, `BurnRateCalculator`, `OverflowCalculator`. El controller solo orquesta y presenta.
**Prerequisito:** Mejoras #1-7 deben estar limpias antes de refactorizar.

### #9 — Prompt nocturno: reconciliación de pagos anticipados
**Problema:** El agente genera coaching sobre el balance sin verificar si hay pagos que cubren períodos futuros. Ejemplo real: arriendo doble en mayo → balance -$453K → parece crisis, no lo es.
**Solución:** Agregar una fase de reconciliación al inicio del análisis nocturno:
> "Antes de evaluar balance o déficit, verifica si hay transacciones committed cuyo monto/descripción sugiera que cubren un período futuro. Ajusta el análisis y explícalo explícitamente."

### #10 — covers_period_month/year en transactions
**Problema:** No se puede saber a qué período corresponde un pago hecho por adelantado.
**Solución:** Dos columnas nullable en `transactions`: `covers_period_month integer` y `covers_period_year integer`. El agente puede inferirlas y proponerlas al usuario; el usuario puede confirmarlas desde la UI.
**Impacto:** `safe_to_deploy` y runway son correctos desde el día 1 del mes siguiente.

---

## Notas de implementación

- Todas las nuevas métricas (#2, #3, #5, #6, #7) se exponen inicialmente como campos adicionales en el endpoint `/api/v1/summary` bajo una sección `health_metrics`.
- No romper contratos existentes — solo agregar, no modificar.
- Cada mejora lleva su spec de test antes de merge.
