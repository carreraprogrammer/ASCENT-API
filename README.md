# boilerplate-rails-api

API base en Rails 8 para autenticacion con JWT, autorizacion RBAC con Pundit y formularios dinamicos guiados por esquema.

El proyecto esta pensado como backend reutilizable para iniciar productos con:
- login, register, refresh token y `me`
- roles dinamicos y permisos granulares en formato `resource:action`
- formularios configurables desde base de datos
- arquitectura por dominios con interactors, repositories, entities y presenters

## Stack

- Ruby 3.3
- Rails 8 API-only
- MariaDB 11
- JWT
- Pundit
- RSpec + FactoryBot
- Docker + Docker Compose

## Arquitectura

La regla principal del proyecto es:

```text
request
  -> controller
  -> interactor
  -> repository
  -> entity
  -> presenter
  -> render json
```

Reglas importantes:
- Los controllers solo orquestan.
- Los interactors contienen logica de aplicacion.
- Solo los repositories tocan ActiveRecord.
- Las entities son POROs.
- Los modelos ActiveRecord solo contienen associations, scopes y validaciones.

La referencia completa esta en [specs/architecture.md](/Users/danielcarrera/Desktop/carrera/BOILER-PLATE-BACK/boilerplate-rails-api/specs/architecture.md).

## Estructura

```text
app/
  controllers/api/v1/
  domains/
    auth/
    authorization/
    forms/
  models/
  services/
db/
  migrate/
  seeds.rb
spec/
specs/
swagger/
```

## Variables de entorno

Usa [.env.example](/Users/danielcarrera/Desktop/carrera/BOILER-PLATE-BACK/boilerplate-rails-api/.env.example) como base.

Variables requeridas:

```env
DATABASE_HOST
DATABASE_PORT
DATABASE_NAME
DATABASE_USERNAME
DATABASE_PASSWORD
JWT_SECRET
JWT_ACCESS_EXPIRY
JWT_REFRESH_EXPIRY
RAILS_ENV
FRONTEND_URL
ALLOWED_ORIGINS
```

## Arranque local con Docker

Levantar servicios:

```bash
docker compose up -d
```

Ver estado:

```bash
docker compose ps
```

Ver logs:

```bash
docker compose logs -f web
docker compose logs -f db
```

La API queda disponible en:

- `http://localhost:3000`
- Swagger: `http://localhost:3000/api-docs`

## Comandos utiles

Migraciones:

```bash
docker compose exec web bundle exec rails db:migrate
```

Seeds:

```bash
docker compose exec web bundle exec rails db:seed
```

RSpec:

```bash
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rspec'
```

RuboCop:

```bash
docker compose run --rm --entrypoint /bin/bash web -lc 'bundle exec rubocop'
```

Consola Rails:

```bash
docker compose exec web bundle exec rails console
```

## Seeds iniciales

El proyecto crea datos base para poder probar autenticacion y permisos:

- Roles: `admin`, `editor`, `viewer`
- Usuarios:
  - `superadmin@boilerplate.dev`
  - `admin@boilerplate.dev`
  - `viewer@boilerplate.dev`

Credenciales de seed:

- `superadmin@boilerplate.dev` / `Admin1234!`
- `admin@boilerplate.dev` / `Admin1234!`
- `viewer@boilerplate.dev` / `Viewer1234!`

## Endpoints principales

Auth:
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `DELETE /api/v1/auth/logout`
- `GET /api/v1/auth/me`

Roles:
- `GET /api/v1/roles`
- `GET /api/v1/roles/:id`
- `POST /api/v1/roles`
- `PATCH /api/v1/roles/:id`
- `DELETE /api/v1/roles/:id`
- `POST /api/v1/roles/:id/assign_permission`
- `DELETE /api/v1/roles/:id/revoke_permission`

Users:
- `GET /api/v1/users`
- `GET /api/v1/users/:id`
- `PATCH /api/v1/users/:id`
- `DELETE /api/v1/users/:id`
- `POST /api/v1/users/:id/assign_role`
- `DELETE /api/v1/users/:id/revoke_role`

Form schemas:
- `GET /api/v1/form_schemas`
- `GET /api/v1/form_schemas/:slug`
- `POST /api/v1/form_schemas`
- `PATCH /api/v1/form_schemas/:slug`
- `DELETE /api/v1/form_schemas/:slug`

## Autenticacion y permisos

- Los access tokens incluyen el arreglo `permissions`.
- Los permisos usan formato `resource:action`.
- `super_admin` bypassa politicas.
- La autorizacion se resuelve con Pundit sobre `Authorization::UserContext`.

## Formularios dinamicos

El dominio `forms` expone esquemas consumibles por frontend. Cada schema define:

- `slug`
- `title`
- `submit_label`
- `submit_endpoint`
- `submit_method`
- `fields`

Esto permite construir formularios desde frontend sin hardcodear toda la estructura.

## Estado actual de calidad

Actualmente el proyecto cumple con la base operativa esperada:

- `docker compose up -d` levanta correctamente
- `bundle exec rspec` pasa
- `bundle exec rubocop` pasa sin offenses

## Documentacion adicional

- [specs/architecture.md](/Users/danielcarrera/Desktop/carrera/BOILER-PLATE-BACK/boilerplate-rails-api/specs/architecture.md)
- [specs/auth.md](/Users/danielcarrera/Desktop/carrera/BOILER-PLATE-BACK/boilerplate-rails-api/specs/auth.md)
- [specs/roles-permissions.md](/Users/danielcarrera/Desktop/carrera/BOILER-PLATE-BACK/boilerplate-rails-api/specs/roles-permissions.md)
- [specs/forms.md](/Users/danielcarrera/Desktop/carrera/BOILER-PLATE-BACK/boilerplate-rails-api/specs/forms.md)

## Permissions cache

Los permisos se embeben en el JWT access token al momento de emitirlo. En esta version no hay una capa extra de cache distribuido. Si despues necesitas invalidacion mas agresiva, ese trabajo deberia vivir dentro del dominio de authorization.
