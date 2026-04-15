# agent-delegation.md — daniel15k-api

Este documento define la transicion desde ownership por `user_id` hacia un
modelo de delegacion compatible con agentes.

---

## Objetivo

Separar claramente:

- identidad humana
- identidad tecnica del agente
- ownership del dominio
- permisos delegados

Sin romper la operacion actual de:

- frontend humano
- daniel15k-agents
- nightly review
- wizard quincenal

---

## Fase implementada en este repo

Esta fase NO cambia aun la forma en que los controllers operan.

El sistema sigue leyendo por `current_user.id`.

Lo que se introduce es la base compatible para la migracion:

- `accounts`
- `agent_types`
- `service_accounts`
- `delegations`
- `account_id` nullable en tablas financieras
- backfill inicial desde `user_id`

---

## Tablas nuevas

### accounts

Owner real de los datos del dominio.

Campos:

- `owner_user_id`
- `name`
- `slug`
- `active`
- `settings`

### agent_types

Catalogo global de tipos de agente.

Ejemplo inicial:

- `finance_coach`

### service_accounts

Identidad tecnica autenticable del runtime.

Ejemplo inicial:

- `daniel15k-brain`

### delegations

Permite expresar:

- que usuario delega
- sobre que cuenta
- a que service account
- para que tipo de agente
- con que scopes

---

## Tablas financieras afectadas

Se agrega `account_id` nullable a:

- `categories`
- `transactions`
- `debts`
- `budgets`
- `income_sources`
- `recurring_obligations`
- `pending_actions`
- `financial_contexts`

En esta fase:

- `user_id` sigue siendo la fuente operativa actual
- `account_id` existe para migracion y compatibilidad futura

---

## Backfill

La migracion crea automaticamente:

1. una `account` por cada `user`
2. `account_id` en los registros financieros actuales
3. el `agent_type` inicial `finance_coach`
4. el `service_account` inicial `daniel15k-brain`
5. una `delegation` activa del owner hacia ese Brain sobre su cuenta

Esto deja la base preparada para el siguiente cambio:

- leer/escribir por `account_id`

Ademas:

- cada usuario nuevo crea su `default_account` automaticamente
- los modelos financieros rellenan `account_id` desde `user_id` al crear registros nuevos
- esto evita que la fase de transicion vuelva a generar datos huerfanos de `account_id`

---

## Garantia de compatibilidad

En esta fase:

- el frontend humano sigue entrando con JWT de usuario
- `daniel15k-agents` puede seguir usando el token legacy
- si se configura `service_token`, el Brain ya puede operar con delegacion
- `user_id` sigue existiendo como compatibilidad, pero el scope financiero ya se resuelve por `account_id`

Pendiente mas adelante:

- memberships multiusuario por account
- auditoria completa `actor_type` / `actor_id`
- remover dependencia operativa de `user_id` en dominio financiero

---

## Operacion

Variables nuevas esperadas por `daniel15k-agents`:

- `DANIEL15K_SERVICE_TOKEN`
- `DANIEL15K_ACCOUNT_ID`
- `DANIEL15K_AGENT_TYPE` (default: `finance_coach`)

Si no existen, el Brain sigue usando el JWT legacy `DANIEL15K_API_TOKEN`.

Tareas utiles:

- `bundle exec rake agent_delegation:list_accounts`
- `SERVICE_ACCOUNT_SLUG=daniel15k-brain SERVICE_ACCOUNT_TOKEN=... bundle exec rake agent_delegation:store_service_token`
