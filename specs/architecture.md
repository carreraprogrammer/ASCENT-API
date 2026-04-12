# architecture.md — boilerplate-rails-api

Este documento es el mapa global del repositorio. Léelo completo antes de leer cualquier spec de dominio.
Ante cualquier ambigüedad, este archivo tiene precedencia sobre los specs de dominio.

---

## Stack

| Capa | Tecnología | Versión |
|------|-----------|---------|
| Framework | Ruby on Rails (API-only) | 8.x |
| Lenguaje | Ruby | 3.3 |
| Base de datos | MariaDB | 11.x |
| Auth | JWT + Refresh Token Rotation | — |
| API | REST — JSON:API spec | — |
| Tests | RSpec + FactoryBot | — |
| Deploy | Railway | — |
| Contenedor | Docker + docker-compose | — |

---

## Estructura de directorios

```
boilerplate-rails-api/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── v1/
│   │           ├── application_controller.rb
│   │           ├── auth_controller.rb
│   │           ├── forms_controller.rb
│   │           └── users_controller.rb
│   ├── domains/
│   │   ├── auth/
│   │   │   ├── entities/
│   │   │   ├── value_objects/
│   │   │   ├── repositories/
│   │   │   ├── interactors/
│   │   │   ├── presenters/
│   │   │   └── events/
│   │   ├── authorization/
│   │   │   ├── entities/
│   │   │   ├── repositories/
│   │   │   ├── interactors/
│   │   │   ├── presenters/
│   │   │   └── policies/
│   │   └── forms/
│   │       ├── entities/
│   │       ├── repositories/
│   │       ├── interactors/
│   │       └── presenters/
│   ├── models/
│   │   ├── user.rb
│   │   ├── role.rb
│   │   ├── permission.rb
│   │   ├── user_role.rb
│   │   ├── role_permission.rb
│   │   └── form_schema.rb
│   └── services/
│       ├── jwt_service.rb
│       └── event_bus.rb
├── config/
│   ├── routes.rb
│   └── initializers/
│       └── cors.rb
├── db/
│   ├── migrate/
│   └── seeds.rb
├── spec/
│   ├── domains/
│   │   ├── auth/
│   │   ├── authorization/
│   │   └── forms/
│   ├── factories/
│   ├── requests/
│   └── support/
├── swagger/
│   └── v1/
│       └── swagger.yaml
├── specs/
│   ├── architecture.md
│   ├── auth.md
│   ├── roles-permissions.md
│   └── forms.md
├── docker/
│   └── entrypoint.sh
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Reglas de arquitectura — sin excepciones

### Flujo obligatorio en cada request

```
request
  → controller          (solo orquesta, cero lógica de negocio)
  → interactor          (lógica de aplicación, orquesta el dominio)
  → repository          (única capa que toca ActiveRecord)
  → entity              (objeto Ruby plano, sin herencia de AR)
  → presenter           (transforma entity a JSON:API hash)
  → render json:        (el controller renderiza el resultado)
```

### Reglas estrictas

- Los **controladores** solo llaman interactors y presenters. Nada más.
- Los **interactors** solo conocen repositorios y value objects de su dominio.
- Los **repositorios** son la única clase que llama a modelos ActiveRecord.
- Las **entities** son POROs (Plain Old Ruby Objects). Sin `< ApplicationRecord`.
- Los **value objects** validan sus invariantes en el constructor y lanzan excepciones de dominio.
- Los **modelos ActiveRecord** en `app/models/` solo tienen: associations, scopes, y validaciones de BD. Cero callbacks de negocio.
- Los **eventos** se emiten al final del interactor via `EventBus`. No bloquean el flujo.
- **Nunca** cruzar dominios directamente. La comunicación entre dominios es via repositorios o eventos.

---

## Convención de respuestas JSON:API

### Respuesta exitosa (recurso único)

```json
{
  "data": {
    "id": "1",
    "type": "users",
    "attributes": {
      "email": "user@example.com",
      "name": "Daniel"
    }
  }
}
```

### Respuesta exitosa (colección)

```json
{
  "data": [
    { "id": "1", "type": "users", "attributes": {} }
  ],
  "meta": { "total": 1 }
}
```

### Respuesta de error

```json
{
  "errors": [
    {
      "status": "422",
      "code": "validation_error",
      "detail": "Email is invalid",
      "source": { "pointer": "/data/attributes/email" }
    }
  ]
}
```

---

## Convenciones de nombres

| Elemento | Convención | Ejemplo |
|----------|-----------|---------|
| Módulos de dominio | `Domain::Layer::Class` | `Authorization::Entities::Role` |
| Interactors | verbo + sustantivo | `AssignRoleToUser` |
| Eventos | sustantivo + pasado | `RoleAssigned` |
| Repositorios | sustantivo + Repository | `RoleRepository` |
| Políticas Pundit | sustantivo + Policy | `UserPolicy` |
| Archivos | snake_case.rb | `assign_role_to_user.rb` |

---

## Variables de entorno requeridas

```
DATABASE_HOST
DATABASE_PORT
DATABASE_NAME
DATABASE_USERNAME
DATABASE_PASSWORD
JWT_SECRET
JWT_ACCESS_EXPIRY       # en segundos, ej: 900
JWT_REFRESH_EXPIRY      # en segundos, ej: 2592000
RAILS_ENV
FRONTEND_URL
ALLOWED_ORIGINS
```

---

## Orden de ejecución para el agente

1. `rails new boilerplate-rails-api --api --database=mysql --skip-test`
2. Agregar gems al Gemfile (ver lista en cada spec de dominio)
3. Crear estructura de carpetas `app/domains/` completa con `.gitkeep`
4. Migraciones en orden: `users` → `roles` → `permissions` → `user_roles` → `role_permissions` → `form_schemas`
5. Implementar dominio `auth` (leer `auth.md`)
6. Implementar dominio `authorization` (leer `roles-permissions.md`)
7. Implementar dominio `forms` (leer `forms.md`)
8. Implementar `JwtService` y `EventBus`
9. Crear controladores y rutas
10. Configurar CORS
11. Crear factories de RSpec
12. Escribir specs
13. Crear seeds
14. Crear `Dockerfile` y `docker-compose.yml`
15. Generar Swagger con rswag
16. Escribir READMEs

---

## Definición de done global

- `docker compose up` levanta sin errores
- `rails db:migrate` corre sin errores
- `rails db:seed` corre sin errores
- `bundle exec rspec` pasa al 100%
- `rubocop` retorna 0 offenses
- Swagger disponible en `/api-docs`
