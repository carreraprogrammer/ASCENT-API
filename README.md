# DANIEL 15K — API

> Un coach personal autónomo. No solo registra lo que gastás — razona sobre tu comportamiento, te alerta antes de que te pases del presupuesto, y te dice qué hacer con cada peso que te sobre.

API REST construida en Rails 8 con arquitectura DDD, diseñada para ser el backend de un sistema de coaching personal multi-módulo. Hoy activo: **Finanzas**. En construcción: Cuerpo, Mente, Social.

La meta no es ganar $15.000 USD/mes. Es convertirse en la persona que se los merece.

---

## Módulos

| Módulo | Estado | Descripción |
|--------|--------|-------------|
| **Finanzas** | 🟡 En construcción | Registro de gastos, presupuestos, deudas, metas de ahorro, coaching nocturno |
| **Cuerpo** | 🔲 Planificado | Suplementos, calorías por foto, ejercicio, sueño |
| **Mente** | 🔲 Planificado | Ritual matutino, journaling, Consejo de Sabios semanal |
| **Social** | 🔲 Planificado | Fragmento diario, debrief nocturno, evidencia acumulada |

---

## Stack

| Capa | Tecnología |
|------|-----------|
| Framework | Ruby on Rails 8 (API-only) |
| Lenguaje | Ruby 3.3 |
| Base de datos | PostgreSQL |
| Auth | JWT + Refresh Token Rotation |
| Autorización | Pundit + Roles/Permisos |
| API | REST — JSON:API spec |
| Tests | RSpec + FactoryBot |
| Docs | Swagger (rswag) — `/api-docs` |
| Deploy | Railway |
| Contenedor | Docker + docker-compose |

---

## Deduplicación y contrato agente/API

### Estrategia actual (abril 2026)

- **El backend solo protege contra duplicados técnicos**: si recibe el mismo `source_event_id` para el mismo `account_id` y `source`, responde 409 Conflict.
- **El agente es responsable de deduplicación semántica**: decide si crear, actualizar, ignorar o pedir aclaración según el contexto conversacional.
- **Ya no se rechazan transacciones por coincidencia de fecha/monto/concepto**: pueden coexistir gastos distintos con mismos valores si provienen de eventos técnicos distintos.

#### Ejemplo de uso de idempotencia técnica

```json
{
  "date": "15/04/2026",
  "concept": "Almuerzo pollo",
  "amount": 14000,
  "transaction_type": "expense",
  "source": "telegram",
  "metadata": {
    "source_event_id": "telegram:message:123456"
  }
}
```

Si el agente reintenta el mismo mensaje, la API responde 409 y no duplica el gasto.

#### Ejemplo de coexistencia de gastos

Dos gastos distintos con mismo monto y fecha pueden coexistir si el `source_event_id` es distinto o nulo.

---
## Setup local

```bash
git clone https://github.com/carreraprogrammer/daniel15k-api.git
cd daniel15k-api

cp .env.example .env
# Completar .env con credenciales locales

docker compose up -d
docker compose exec web bundle exec rails db:migrate
docker compose exec web bundle exec rails db:seed
```

API disponible en `http://localhost:3000`
Swagger en `http://localhost:3000/api-docs`

### Comandos útiles

```bash
# Tests
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rspec'

# Linter
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rubocop'

# Consola Rails
docker compose exec web bundle exec rails console

# Migraciones
docker compose exec web bundle exec rails db:migrate
```

---

## Arquitectura

El flujo obligatorio en cada request:

```
Request HTTP
  → Controller          (orquesta, cero lógica de negocio)
  → Interactor          (lógica de aplicación)
  → Repository          (única capa que toca ActiveRecord)
  → Entity              (PORO — Plain Old Ruby Object)
  → Presenter           (transforma a JSON:API)
  → render json
```

Ver [specs/architecture.md](specs/architecture.md) para reglas completas.

---

## Módulo Finanzas — Consumo de la API

### Autenticación

Todos los endpoints requieren JWT en el header:

```
Authorization: Bearer <access_token>
```

Obtener token:

```http
POST /api/v1/auth/login

{ "email": "daniel@example.com", "password": "..." }
```

```json
{
  "data": {
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 3600
  }
}
```

---

### Transacciones

#### Crear
```http
POST /api/v1/transactions

{
  "date": "11/04",
  "concept": "Almuerzo D1",
  "product": "nequi",
  "amount": 15000,
  "category_id": 3,
  "subcategory_id": 12,
  "source": "telegram",
  "status": "confirmed"
}
```

| Campo | Tipo | Req | Descripción |
|-------|------|-----|-------------|
| `date` | string DD/MM | ✅ | Fecha en hora Colombia |
| `concept` | string | ✅ | Descripción libre |
| `product` | string | ✅ | `nequi` · `tc7248` · `tc1322` · `debito` · `bre-b` |
| `amount` | integer | ✅ | Pesos colombianos, siempre positivo |
| `category_id` | integer | ✅ | |
| `subcategory_id` | integer | — | |
| `source` | string | — | `telegram` · `gmail` · `manual` |
| `status` | string | — | `confirmed` · `pending` · `projected` |
| `metadata` | object | — | Datos crudos del mensaje original |

#### Listar por mes
```http
GET /api/v1/transactions?month=04&year=2026
```

#### Pendientes de aclaración
```http
GET /api/v1/transactions/pending
```

#### Actualizar (resolver ⚠️ pendiente)
```http
PATCH /api/v1/transactions/:id

{ "status": "confirmed", "category_id": 5, "subcategory_id": 18 }
```

---

### Categorías

Las categorías están organizadas por **agencia** (no por tipo contable). Esto permite coaching conductual real: no es lo mismo que te hayas pasado en "alimentación" que en "discrecional".

| Categoría | Código | Descripción |
|-----------|--------|-------------|
| Comprometido | `committed` | No negociable (arriendo, créditos, servicios fijos) |
| Necesario | `necessary` | Puedo optimizar pero no eliminar (mercado, gasolina) |
| Discrecional | `discretionary` | Decisión activa mía (restaurantes, ropa, ocio) |
| Inversión | `investment` | Retorno futuro (cursos, suplementos, herramientas) |
| Social | `social` | Relaciones (regalos, salidas con amigos) |
| Ingreso | `income` | Entradas de dinero |
| Desconocido | `unknown` | IA no clasificó — requiere aclaración |

```http
GET  /api/v1/categories
POST /api/v1/categories        # el agente puede crear categorías nuevas
```

---

### Fuentes de ingreso

```http
GET  /api/v1/income_sources
POST /api/v1/income_sources

{
  "name": "EMAPTA Q1",
  "expected_day_from": 1,
  "expected_day_to": 5,
  "expected_amount": 3335000,
  "is_variable": false
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `name` | string | Nombre descriptivo |
| `expected_day_from` | integer 1-31 | Día más temprano en que puede llegar |
| `expected_day_to` | integer 1-31 | Día más tardío (debe ser >= from) |
| `expected_amount` | integer | Monto esperado en pesos |
| `is_variable` | boolean | Si el monto varía (ej: freelance) |

```http
PATCH  /api/v1/income_sources/:id
DELETE /api/v1/income_sources/:id   # soft-delete (active=false)
```

---

### Obligaciones recurrentes

Gastos fijos que se repiten todos los meses (arriendo, créditos, etc.).

```http
GET  /api/v1/recurring_obligations
POST /api/v1/recurring_obligations

{
  "name": "Arriendo",
  "amount": 2500000,
  "due_day": 5,
  "category_id": 3
}
```

```http
PATCH  /api/v1/recurring_obligations/:id
DELETE /api/v1/recurring_obligations/:id   # soft-delete (active=false)
```

---

### Presupuestos

```http
GET  /api/v1/budgets?month=04&year=2026
POST /api/v1/budgets

{ "category_id": 3, "month": 4, "year": 2026, "amount_limit": 500000 }
```

---

### Deudas

```http
GET  /api/v1/debts
POST /api/v1/debts

{
  "name": "CrediExpress #290742",
  "current_balance": 5196000,
  "monthly_payment": 866000,
  "interest_rate": 2.1,
  "debt_type": "personal_loan",
  "payoff_date": "2026-12-01"
}
```

`PATCH /api/v1/debts/:id` — si `current_balance` llega a 0, pasa a `paid_off` automáticamente.

---

### Acciones pendientes (flujos interactivos)

```http
GET   /api/v1/pending_actions/active     # devuelve el PendingAction activo o null
POST  /api/v1/pending_actions
PATCH /api/v1/pending_actions/:id

{
  "action_type": "budget_planning",
  "current_step": 0,
  "total_steps": 8,
  "context": {},
  "status": "waiting_response",
  "expires_at": "2026-04-22T13:00:00Z"
}
```

---

### Resumen mensual

El endpoint más importante. Lo consume el agente nocturno para generar el coaching.

```http
GET /api/v1/summary?month=04&year=2026
```

```json
{
  "data": {
    "period": "abril 2026",
    "income": 6435146,
    "categories": {
      "committed":     { "budget": 4000000, "spent": 3200000, "pct": 80 },
      "necessary":     { "budget": 800000,  "spent": 650000,  "pct": 81 },
      "discretionary": {
        "budget": 500000, "spent": 480000, "pct": 96,
        "burn_rate_alert": "A este ritmo gastarás $640.000 — 28% sobre presupuesto"
      }
    },
    "savings_goals": [
      { "name": "Matrícula moto 2027", "monthly_target": 88888, "contributed": 0, "on_track": false }
    ],
    "financial_phase": "debt_payoff",
    "financial_score": 72,
    "insights": [
      "Llevas 11 días sin delivery. Tu mejor racha este año.",
      "Discrecional al 96% — quedan 19 días de mes."
    ]
  }
}
```

---

### Contexto financiero

Define la fase actual y la estrategia del usuario. El agente lee esto para razonar.

```http
GET   /api/v1/financial_context
PATCH /api/v1/financial_context

{
  "phase": "debt_payoff",
  "strategy": "snowball",
  "notes": "Prioridad: liquidar CrediExpress antes de diciembre"
}
```

Fases disponibles: `debt_payoff` · `emergency_fund` · `investing` · `wealth_building`

---

## Endpoints Auth y Roles (heredados del boilerplate)

```
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
DELETE /api/v1/auth/logout
GET    /api/v1/auth/me

GET    /api/v1/roles
POST   /api/v1/roles
PATCH  /api/v1/roles/:id
POST   /api/v1/roles/:id/assign_permission

GET    /api/v1/users
PATCH  /api/v1/users/:id
POST   /api/v1/users/:id/assign_role
```

---

## Variables de entorno

```bash
DATABASE_URL=postgresql://...
JWT_SECRET=
JWT_ACCESS_EXPIRY=3600       # 1 hora
JWT_REFRESH_EXPIRY=2592000   # 30 días
RAILS_ENV=development
FRONTEND_URL=http://localhost:5173
ALLOWED_ORIGINS=http://localhost:5173
```

---

## Documentación adicional

- [specs/architecture.md](specs/architecture.md) — reglas de arquitectura DDD
- [specs/auth.md](specs/auth.md) — flujo de autenticación
- [specs/roles-permissions.md](specs/roles-permissions.md) — RBAC
- [specs/finanzas/plan.md](specs/finanzas/plan.md) — plan completo del módulo Finanzas
- [specs/finanzas/fases.md](specs/finanzas/fases.md) — fases de ejecución con criterios de aceptación
