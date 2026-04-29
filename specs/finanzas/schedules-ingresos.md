# Schedules de Fuentes de Ingreso

> Estado: ⚠️ parcialmente supersedido — el modelo actual de `income_sources` incorporó parte de este diseño; verificar código antes de usar
> Última actualización: 2026-04-17

## Objetivo

Separar la fuente de ingreso de sus ventanas de llegada sin romper el contrato actual del sistema.

## Cambio de dominio

Antes:

- `income_sources` intentaba representar al mismo tiempo:
  - la fuente estructural
  - el monto mensual total
  - la frecuencia
  - la ventana esperada de llegada

Eso obligaba a workarounds como duplicar filas para un ingreso quincenal.

Ahora:

- `income_sources` representa la fuente estructural
- `income_source_schedules` representa una o varias ventanas esperadas dentro del mes

## Contrato actual

`income_sources` conserva:

- `name`
- `classification`
- `cadence`
- `reliability_score`
- `notes`
- `expected_day_from`
- `expected_day_to`
- `expected_amount`

Los tres campos `expected_*` quedan como denormalización agregada:

- `expected_day_from` = mínimo de schedules
- `expected_day_to` = máximo de schedules
- `expected_amount` = suma mensual de schedules

## API

`POST /api/v1/income_sources`
`PATCH /api/v1/income_sources/:id`

aceptan:

- payload legacy con `expected_day_from`, `expected_day_to`, `expected_amount`
- payload nuevo con `schedules`

Si llega `schedules`, esa colección se vuelve la fuente de verdad.

## Compatibilidad

El Brain y algunos filtros siguen leyendo `expected_*`.

Por eso el repositorio sincroniza siempre:

- padre <- schedules

Y si llega un update legacy sin `schedules`, se reemplaza el schedule principal con esos valores para no dejar inconsistencia.

## Casos soportados

- mensual: 1 schedule
- quincenal: 2 schedules
- semanal: 4 schedules
- irregular: 1 schedule de mes completo

## Validación hecha

- sintaxis Ruby OK en modelos, repositorio, controller y migración
- request spec actualizada con casos:
  - create legacy
  - create con schedules
  - update legacy
  - update weekly con schedules

`rspec` no pudo ejecutarse localmente porque el host no tiene acceso al Postgres de test.

---

## Implementación en el Brain

El Brain es compatible con el modelo nuevo de schedules sin romper los flujos conversacionales existentes.

### Qué hace el Brain

- lee `schedules` cuando el API los devuelve
- crea `income_sources` con `cadence + schedules`
- no asume una sola ventana por ingreso
- muestra el breakdown de ventanas si el source trae `schedules`
- `rails_api.py` y `rails_http.py` aceptan: `cadence`, `schedules`, `notes`

### Income wizard en el Brain

- pregunta cadencia explícita
- pide el monto por evento cuando la cadencia es quincenal o semanal
- calcula el total mensual internamente antes de persistir `expected_amount`
- soporta mensual / quincenal / semanal / irregular
- crea una sola fuente por ingreso aunque tenga varias ventanas
- pide confiabilidad solo para ingreso variable

### Deuda técnica pendiente

El Brain sigue conviviendo con campos legacy (`expected_day_from`, `expected_day_to`, `expected_amount`) porque la API los usa como denormalización de lectura. Eso no bloquea ningún flujo actual.
