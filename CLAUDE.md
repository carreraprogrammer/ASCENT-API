# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All commands run inside Docker:

```bash
# Start containers
docker compose up -d

# Run all tests
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rspec'

# Run a single spec file
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rspec spec/domains/finanzas/interactors/create_transaction_spec.rb'

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
| `LiquidityProjection` | Calculates `safe_to_deploy` — universal guardrail for the agent |
| `DetectCompletenessState` | 5-dimension profile: `income_profile`, `debts`, `recurring_expenses`, `strategy`, `monthly_plan` |
| `AgentPreflight` | Agent evaluates gaps before acting |
| `InsightDriftChecker` | Guards daily insight regeneration against trivial drift |
| `RegisterDebtPayment` | Registers payment atomically, updates debt balance |

**Key invariants:**
- `recurring_obligations.amount` is the source of truth for monthly cash impact, not `debts.monthly_payment`.
- `source_event_id` deduplication is technical only — the agent is responsible for semantic deduplication.
- `safe_to_deploy` = money available after next cycle's commitments. Every agent recommendation must respect this guardrail.
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

**Fase 3 (en progreso):** Living Budget Integration. Core plan mensual is complete. Pending: Fase A CTAs, Fase E agent/backend coherence, plan rolling UI, `ProposeBudget` with historical patterns, dedicated chat UI.

**Fase 3.5 (spec ready, not implemented):** Payment sources + credit card cycle (eliminates double-counting: individual purchases vs. monthly bank payment).

See `specs/finanzas/fases.md` for full phase tracker. See `specs/finanzas/living-budget.md` for the active spec.

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Domain modules | `Domain::Layer::Class` | `Finanzas::Interactors::CreateTransaction` |
| Interactors | verb + noun | `RegisterDebtPayment` |
| Repositories | noun + Repository | `TransactionRepository` |
| Events | noun + past tense | `UserRegistered` |
| Pundit policies | noun + Policy | `UserPolicy` |
| Files | snake_case.rb | `register_debt_payment.rb` |
