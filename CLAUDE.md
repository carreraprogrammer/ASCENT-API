# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All commands run inside Docker:

```bash
# Start containers
docker compose up -d

# Run all tests (el contenedor corre RAILS_ENV=production por defecto → forzar test;
# docker-compose ya monta el código vivo (bind-mount .:/app))
docker compose run --rm -e RAILS_ENV=test --entrypoint /bin/bash web -lc 'bundle exec rspec'

# Run a single spec file
docker compose run --rm -e RAILS_ENV=test --entrypoint /bin/bash web -lc 'bundle exec rspec spec/domains/finanzas/interactors/create_transaction_spec.rb'

# Linter
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rubocop'

# Rails console
docker compose exec web bundle exec rails console

# Migrations
docker compose exec web bundle exec rails db:migrate

# Seeds (regenerates ServiceAccount.token_hash from DANIEL15K_SERVICE_TOKEN)
docker compose exec web bundle exec rails db:seed
```

Swagger UI: `http://localhost:3000/api-docs`

## Architecture

Rails 8 API-only with DDD. Every request must follow this flow — no shortcuts:

```
Request → Controller → Interactor → Repository → Entity → Presenter → render json
```

**Rules (no exceptions):**
- Controllers only call interactors and presenters. Zero business logic.
- Interactors only know repositories and value objects from their own domain.
- Repositories are the only layer that touches ActiveRecord models.
- Entities are POROs — no `< ApplicationRecord`.
- ActiveRecord models in `app/models/` only contain: associations, scopes, and DB validations. No business callbacks.
- Cross-domain communication happens only via repositories or EventBus events.
- Events are published at the end of the interactor via `EventBus.publish(...)`. They never block the flow.

**Domain modules** live in `app/domains/`:
- `auth` — JWT + refresh token rotation (token reuse detection invalidates all sessions)
- `authorization` — Pundit-based RBAC (roles + permissions)
- `forms` — dynamic form schemas
- `users` — user profile
- `finanzas` — all finance features (active module)

## Finanzas Domain

The core module. Key interactors in `app/domains/finanzas/interactors/`:

| Interactor | Purpose |
|------------|---------|
| `CreateTransaction` | Creates expense/income; runs `DetectTransactionStructure` on `expense+confirmed` |
| `DetectTransactionStructure` | Matches transaction to recurring_obligation or sinking_fund |
| `WizardData` | Proposes monthly budget: income sources + blocked lines + sinking fund suggestions |
| `GenerateMonthlyFinancialPlan` | Generates draft plan for the month |
| `CloseMonthlyPlan` | Closes month + saves `execution_snapshot` |
| `ProposeBudget` | Reads last 3 closed plans for `consistently_over` / `income_overestimated` patterns |
| `CashFlowRunway` | Calculates `commitment_gap` ("margen libre") — universal guardrail for the agent. Every user-facing formula is documented in `specs/finanzas/glosario-calculos.md` |
| `DetectCompletenessState` | 5-dimension profile: `income_profile`, `debts`, `recurring_expenses`, `strategy`, `monthly_plan` |
| `AgentPreflight` | Agent evaluates gaps before acting |
| `InsightDriftChecker` | Guards daily insight regeneration against trivial drift |
| `RegisterDebtPayment` | Registers payment atomically, updates debt balance |

**Key invariants:**
- `recurring_obligations.amount` is the source of truth for monthly cash impact, not `debts.monthly_payment`.
- `source_event_id` deduplication is technical only — the agent is responsible for semantic deduplication.
- `commitment_gap` (margen libre) = money available after the commitments and daily burn until the next income. Every agent recommendation must respect this guardrail. (`safe_to_deploy`/`LiquidityProjection` was the old name; the interactor no longer exists.)
- A `RecurringObligation` with subcategory `creditos` requires `source_type=Debt`. `POST /debts` suggests creating the obligation if it doesn't exist.

## Authentication

**JWT (human users):** `Authorization: Bearer <access_token>`

**Service account (Brain agent):**
```
Authorization: Bearer <DANIEL15K_SERVICE_TOKEN>
X-Account-Id: <account_id>
X-Agent-Type: finance_coach
```
Authenticates via SHA-256 of the token stored in `service_accounts.token_hash`.

## API Response Format (JSON:API)

```json
{ "data": { "id": "1", "type": "transactions", "attributes": {} } }
{ "data": [...], "meta": { "total": 1 } }
{ "errors": [{ "status": "422", "code": "validation_error", "detail": "...", "source": { "pointer": "/data/attributes/field" } }] }
```

## Current Phase

**Fases 1–4 + 3.5:** Completadas. Transacciones, plan mensual, deudas, metas, gamificación (backend), medios de pago, agente nocturno, web chat.

**Fase 5 (en progreso):** La Cara Viva. Backend de gamificación + avatar flotante completos. Pendiente: chat dedicado funcional, barra XP en Dashboard, motor conductual COM-B, `user_level` en contexto del agente.

**Multi-usuario (Fase 0 del roadmap):** Completo. `ProvisionAccount` idempotente crea Account + AccountProgress + Delegation automáticamente en cada registro (email o Google OAuth). Gmail OAuth completo: tokens cifrados, modo híbrido de búsqueda (senders configurados o keywords genéricos), auto-discovery de remitentes.

**Próximo:** Fase 0.7 — chat dedicado + barra XP + racha en Dashboard. Ver `specs/producto/roadmap-primeros-10.md` para el tracker de multi-usuario. Ver `specs/finanzas/fases.md` para el tracker de features.

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Domain modules | `Domain::Layer::Class` | `Finanzas::Interactors::CreateTransaction` |
| Interactors | verb + noun | `RegisterDebtPayment` |
| Repositories | noun + Repository | `TransactionRepository` |
| Events | noun + past tense | `UserRegistered` |
| Pundit policies | noun + Policy | `UserPolicy` |
| Files | snake_case.rb | `register_debt_payment.rb` |
