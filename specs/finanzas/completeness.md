# Completeness y Agent Preflight

> Estado: ✅ implementado — verificar código para estado real
> Última actualización: 2026-04-17

## Objetivo

Introducir una capa mínima de completitud y un `preflight` operativo antes de intents de planeación.

## Qué quedó implementado

- `GET /api/v1/completeness`
- `POST /api/v1/agents/preflight`
- interactor `DetectCompletenessState`
- interactor `AgentPreflight`

## Dimensiones evaluadas

- `income_profile`
- `debts`
- `recurring_expenses`
- `strategy`
- `monthly_plan`

## Estados usados en este milestone

- `missing`
- `partial`
- `sufficient`
- `stale`

`conflicting` queda reservado para una siguiente iteración.

## Regla operativa

El backend decide si un intent debe:

- continuar normal
- continuar con `soft_nudge`
- bloquearse y abrir wizard

### Intents soportados

- `budgeting`
- `monthly_status`
- `overflow`
- `general`

## Criterios de aceptación cubiertos

- existe estado mínimo de completitud para las 5 dimensiones
- el agente puede consultar `preflight`
- `budgeting` se bloquea si faltan bases críticas del mes
- `monthly_status` puede responder con nudge en vez de bloqueo
- la decisión de bloqueo ya no vive solo en prompts

## Lo que todavía no entra

- `wizard_sessions`
- cache/materialización de completitud
- `question_event_log`
- prioridad por `confidence`
- estado `confirmed` separado de `sufficient`

---

## Implementación en el Brain

### Qué hace el Brain antes de responder intents de planeación

- detecta el intent del mensaje: `budgeting`, `monthly_status`, `overflow`
- llama `POST /api/v1/agents/preflight`
- decide localmente:
  - `allow` → flujo normal
  - `soft_nudge` → responde igual pero cierra con recordatorio breve
  - `block` → no improvisa, dispara el wizard mensual

### Routing de mensajes a wizard activo

El webhook reenvía mensajes de texto al wizard activo cuando existe un `PendingAction` de:
- `budget_planning`
- `financial_context_setup`

Esto evita que respuestas por texto se vayan por error al chat general mientras hay un wizard en curso.
