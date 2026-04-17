# Fase 3.3 - Overflow y uso operativo del plan

Fecha: 2026-04-17

## Objetivo

Hacer que el `monthly_financial_plan` deje de ser decorativo y empiece a orientar:

- resumen mensual
- consultas sobre ingreso extra
- coaching nocturno

## Qué quedó implementado

- `summary` ahora expone `overflow_status`
- `overflow_status` calcula:
  - `base_budget_income`
  - `confirmed_income`
  - `expected_variable_income`
  - `realized_overflow`
  - `remaining_expected_overflow`
  - `suggested_destination`
  - `suggested_action`

## Regla usada en este milestone

`realized_overflow = max(income_confirmed - base_budget_income, 0)`

Esto convierte el ingreso confirmado por encima de la base del plan en señal operativa sin inflar el presupuesto base.

## Alcance

En este milestone el sistema:

- interpreta overflow
- lo refleja en `summary`
- y lo pone disponible para agentes

Todavía no:

- ejecuta asignaciones automáticas
- persiste una “aplicación” formal del overflow
- valida si el usuario ya movió efectivamente ese extra al destino sugerido

## Criterios de aceptación cubiertos

- el sistema soporta base vs variable en la práctica del mes
- cuando entra ingreso extra, `summary` lo refleja como overflow
- el overflow no infla el presupuesto base
- el backend sugiere destino según `overflow_rule`
