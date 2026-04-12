# roles-permissions.md — boilerplate-rails-api

Dominio: `authorization`
Responsabilidad: gestionar roles dinámicos, permisos granulares, y autorización de acciones en toda la API.
Leer `architecture.md` antes de implementar este dominio.

---

## Gems requeridas

Agregar al Gemfile antes de implementar:

```ruby
gem 'pundit'           # autorización basada en políticas
gem 'jwt'              # ya incluido en auth, no duplicar
```

Ejecutar `bundle install` después de modificar el Gemfile.

---

## Modelo de datos

### Diseño RBAC completo

```
users ──< user_roles >── roles ──< role_permissions >── permissions
```

Un usuario puede tener múltiples roles.
Un rol puede tener múltiples permisos.
Los permisos son strings granulares en formato `resource:action`.

### Migraciones — crear en este orden exacto

#### 1. roles

```ruby
create_table :roles do |t|
  t.string  :name,        null: false
  t.string  :slug,        null: false
  t.text    :description
  t.boolean :active,      null: false, default: true
  t.timestamps
end

add_index :roles, :slug, unique: true
```

#### 2. permissions

```ruby
create_table :permissions do |t|
  t.string :resource, null: false   # ej: "users", "forms", "roles"
  t.string :action,   null: false   # ej: "create", "read", "update", "destroy", "manage"
  t.text   :description
  t.timestamps
end

add_index :permissions, [:resource, :action], unique: true
```

#### 3. role_permissions

```ruby
create_table :role_permissions do |t|
  t.references :role,       null: false, foreign_key: true
  t.references :permission, null: false, foreign_key: true
  t.timestamps
end

add_index :role_permissions, [:role_id, :permission_id], unique: true
```

#### 4. user_roles

```ruby
create_table :user_roles do |t|
  t.references :user, null: false, foreign_key: true
  t.references :role, null: false, foreign_key: true
  t.datetime   :expires_at             # nil = sin expiración
  t.timestamps
end

add_index :user_roles, [:user_id, :role_id], unique: true
```

### Modificación a la tabla users

Agregar en una migración separada:

```ruby
add_column :users, :super_admin, :boolean, null: false, default: false
```

`super_admin: true` bypasea todas las políticas Pundit. Solo existe un super admin en seeds.

---

## Modelos ActiveRecord

Los modelos solo definen associations, scopes, y validaciones de BD. Cero lógica de negocio.

### app/models/role.rb

```ruby
class Role < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }

  scope :active, -> { where(active: true) }
end
```

### app/models/permission.rb

```ruby
class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :resource, presence: true
  validates :action,   presence: true
  validates :resource, uniqueness: { scope: :action }

  scope :for_resource, ->(resource) { where(resource: resource) }

  def slug
    "#{resource}:#{action}"
  end
end
```

### app/models/user_role.rb

```ruby
class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role

  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
end
```

### app/models/role_permission.rb

```ruby
class RolePermission < ApplicationRecord
  belongs_to :role
  belongs_to :permission
end
```

### Modificación a app/models/user.rb

Agregar estas líneas al modelo User existente:

```ruby
has_many :user_roles, dependent: :destroy
has_many :roles, through: :user_roles
has_many :permissions, through: :roles
```

---

## Dominio: Authorization

### Entities

#### app/domains/authorization/entities/role.rb

```ruby
module Authorization
  module Entities
    class Role
      attr_reader :id, :name, :slug, :description, :active, :permissions

      def initialize(id:, name:, slug:, description: nil, active: true, permissions: [])
        @id          = id
        @name        = name
        @slug        = slug
        @description = description
        @active      = active
        @permissions = permissions
      end
    end
  end
end
```

#### app/domains/authorization/entities/permission.rb

```ruby
module Authorization
  module Entities
    class Permission
      attr_reader :id, :resource, :action, :description

      def initialize(id:, resource:, action:, description: nil)
        @id          = id
        @resource    = resource
        @action      = action
        @description = description
      end

      def slug
        "#{resource}:#{action}"
      end
    end
  end
end
```

### Repositories

#### app/domains/authorization/repositories/role_repository.rb

```ruby
module Authorization
  module Repositories
    class RoleRepository
      def find(id)
        record = ::Role.active.find(id)
        map_to_entity(record)
      end

      def find_by_slug(slug)
        record = ::Role.active.find_by!(slug: slug)
        map_to_entity(record)
      end

      def all
        ::Role.active.includes(:permissions).map { |r| map_to_entity(r) }
      end

      def create(name:, slug:, description: nil)
        record = ::Role.create!(name: name, slug: slug, description: description)
        map_to_entity(record)
      end

      def assign_permission(role_id:, permission_id:)
        ::RolePermission.find_or_create_by!(role_id: role_id, permission_id: permission_id)
      end

      def revoke_permission(role_id:, permission_id:)
        ::RolePermission.find_by(role_id: role_id, permission_id: permission_id)&.destroy!
      end

      private

      def map_to_entity(record)
        permissions = record.permissions.map do |p|
          Authorization::Entities::Permission.new(
            id: p.id, resource: p.resource, action: p.action, description: p.description
          )
        end

        Authorization::Entities::Role.new(
          id: record.id, name: record.name, slug: record.slug,
          description: record.description, active: record.active,
          permissions: permissions
        )
      end
    end
  end
end
```

#### app/domains/authorization/repositories/permission_repository.rb

```ruby
module Authorization
  module Repositories
    class PermissionRepository
      def all
        ::Permission.all.map { |p| map_to_entity(p) }
      end

      def find(id)
        map_to_entity(::Permission.find(id))
      end

      def find_by_slug(slug)
        resource, action = slug.split(':')
        record = ::Permission.find_by!(resource: resource, action: action)
        map_to_entity(record)
      end

      def create(resource:, action:, description: nil)
        record = ::Permission.create!(resource: resource, action: action, description: description)
        map_to_entity(record)
      end

      private

      def map_to_entity(record)
        Authorization::Entities::Permission.new(
          id: record.id, resource: record.resource,
          action: record.action, description: record.description
        )
      end
    end
  end
end
```

#### app/domains/authorization/repositories/user_role_repository.rb

```ruby
module Authorization
  module Repositories
    class UserRoleRepository
      def assign(user_id:, role_id:, expires_at: nil)
        ::UserRole.find_or_create_by!(user_id: user_id, role_id: role_id) do |ur|
          ur.expires_at = expires_at
        end
      end

      def revoke(user_id:, role_id:)
        ::UserRole.find_by(user_id: user_id, role_id: role_id)&.destroy!
      end

      def permissions_for_user(user_id)
        ::Permission
          .joins(roles: :user_roles)
          .where(user_roles: { user_id: user_id })
          .where('user_roles.expires_at IS NULL OR user_roles.expires_at > ?', Time.current)
          .distinct
          .map { |p| "#{p.resource}:#{p.action}" }
      end

      def roles_for_user(user_id)
        ::Role
          .joins(:user_roles)
          .where(user_roles: { user_id: user_id })
          .active
          .where('user_roles.expires_at IS NULL OR user_roles.expires_at > ?', Time.current)
      end
    end
  end
end
```

### Interactors

#### app/domains/authorization/interactors/assign_role_to_user.rb

```ruby
module Authorization
  module Interactors
    class AssignRoleToUser
      def initialize(
        role_repo: Repositories::RoleRepository.new,
        user_role_repo: Repositories::UserRoleRepository.new
      )
        @role_repo      = role_repo
        @user_role_repo = user_role_repo
      end

      def call(user_id:, role_slug:, expires_at: nil)
        role = @role_repo.find_by_slug(role_slug)
        @user_role_repo.assign(user_id: user_id, role_id: role.id, expires_at: expires_at)
        role
      end
    end
  end
end
```

#### app/domains/authorization/interactors/revoke_role_from_user.rb

```ruby
module Authorization
  module Interactors
    class RevokeRoleFromUser
      def initialize(user_role_repo: Repositories::UserRoleRepository.new)
        @user_role_repo = user_role_repo
      end

      def call(user_id:, role_slug:)
        role = ::Role.find_by!(slug: role_slug)
        @user_role_repo.revoke(user_id: user_id, role_id: role.id)
      end
    end
  end
end
```

#### app/domains/authorization/interactors/fetch_user_permissions.rb

```ruby
module Authorization
  module Interactors
    class FetchUserPermissions
      def initialize(user_role_repo: Repositories::UserRoleRepository.new)
        @user_role_repo = user_role_repo
      end

      # Retorna array de strings: ["users:read", "forms:create", ...]
      def call(user_id:)
        @user_role_repo.permissions_for_user(user_id)
      end
    end
  end
end
```

### Presenters

#### app/domains/authorization/presenters/role_presenter.rb

```ruby
module Authorization
  module Presenters
    class RolePresenter
      def self.single(entity)
        {
          data: {
            id:         entity.id.to_s,
            type:       'roles',
            attributes: {
              name:        entity.name,
              slug:        entity.slug,
              description: entity.description,
              active:      entity.active,
              permissions: entity.permissions.map(&:slug)
            }
          }
        }
      end

      def self.collection(entities)
        {
          data: entities.map { |e| single(e)[:data] },
          meta: { total: entities.size }
        }
      end
    end
  end
end
```

---

## Pundit — Políticas

### Concern: Authorizable

Crear `app/controllers/concerns/authorizable.rb`:

```ruby
module Authorizable
  extend ActiveSupport::Concern

  included do
    include Pundit::Authorization
    after_action :verify_authorized, except: :index
    after_action :verify_policy_scoped, only: :index

    rescue_from Pundit::NotAuthorizedError do |e|
      render json: {
        errors: [{
          status:  '403',
          code:    'forbidden',
          detail:  'No tienes permisos para realizar esta acción'
        }]
      }, status: :forbidden
    end
  end

  # Helpers disponibles en cualquier controller que incluya este concern
  def current_permissions
    @current_permissions ||=
      Authorization::Interactors::FetchUserPermissions.new.call(user_id: current_user.id)
  end

  def can?(permission_slug)
    return true if current_user.super_admin?
    current_permissions.include?(permission_slug)
  end
end
```

### app/controllers/api/v1/application_controller.rb

```ruby
module Api
  module V1
    class ApplicationController < ActionController::API
      include Authorizable

      before_action :authenticate_request!

      private

      def authenticate_request!
        token = request.headers['Authorization']&.split(' ')&.last
        payload = JwtService.decode(token)
        @current_user = ::User.find(payload[:user_id])
      rescue JwtService::ExpiredToken, JwtService::InvalidToken, ActiveRecord::RecordNotFound
        render json: {
          errors: [{ status: '401', code: 'unauthorized', detail: 'Token inválido o expirado' }]
        }, status: :unauthorized
      end

      def current_user
        @current_user
      end
    end
  end
end
```

### Políticas

#### app/domains/authorization/policies/application_policy.rb

```ruby
module Authorization
  module Policies
    class ApplicationPolicy
      attr_reader :user, :record

      def initialize(user, record)
        raise Pundit::NotAuthorizedError, 'Usuario no autenticado' unless user
        @user   = user
        @record = record
      end

      def index?   = false
      def show?    = false
      def create?  = false
      def update?  = false
      def destroy? = false

      private

      def super_admin?
        user.super_admin?
      end

      def has_permission?(slug)
        return true if super_admin?
        # Delega al interactor — no llama a AR directamente
        Authorization::Interactors::FetchUserPermissions
          .new.call(user_id: user.id).include?(slug)
      end
    end
  end
end
```

#### app/domains/authorization/policies/user_policy.rb

```ruby
module Authorization
  module Policies
    class UserPolicy < ApplicationPolicy
      def index?   = has_permission?('users:read')
      def show?    = has_permission?('users:read') || user.id == record.id
      def create?  = has_permission?('users:create')
      def update?  = has_permission?('users:update') || user.id == record.id
      def destroy? = has_permission?('users:destroy')

      def assign_role? = has_permission?('users:assign_role')
      def revoke_role? = has_permission?('users:revoke_role')
    end
  end
end
```

#### app/domains/authorization/policies/role_policy.rb

```ruby
module Authorization
  module Policies
    class RolePolicy < ApplicationPolicy
      def index?   = has_permission?('roles:read')
      def show?    = has_permission?('roles:read')
      def create?  = has_permission?('roles:create')
      def update?  = has_permission?('roles:update')
      def destroy? = has_permission?('roles:destroy')
    end
  end
end
```

---

## JWT — Permisos en el payload

El `JwtService` debe incluir los permisos resueltos en el access token.
Modificar `app/services/jwt_service.rb` para que el payload sea:

```ruby
{
  user_id:     user.id,
  email:       user.email,
  super_admin: user.super_admin,
  permissions: Authorization::Interactors::FetchUserPermissions.new.call(user_id: user.id),
  jti:         SecureRandom.uuid,
  exp:         Time.current.to_i + ENV['JWT_ACCESS_EXPIRY'].to_i
}
```

Los permisos en el JWT evitan queries adicionales en cada request.
El array de permisos se recalcula cada vez que se emite un nuevo access token.

---

## Endpoints

### Rutas a agregar en config/routes.rb

```ruby
namespace :api do
  namespace :v1 do
    # ... rutas existentes ...

    resources :roles, only: [:index, :show, :create, :update, :destroy] do
      member do
        post   :assign_permission
        delete :revoke_permission
      end
    end

    resources :users, only: [:index, :show, :update, :destroy] do
      member do
        post   :assign_role
        delete :revoke_role
      end
    end
  end
end
```

### Tabla de endpoints

| Método | Ruta | Permiso requerido | Descripción |
|--------|------|------------------|-------------|
| GET | `/api/v1/roles` | `roles:read` | Listar todos los roles |
| GET | `/api/v1/roles/:id` | `roles:read` | Ver un rol |
| POST | `/api/v1/roles` | `roles:create` | Crear rol |
| PATCH | `/api/v1/roles/:id` | `roles:update` | Actualizar rol |
| DELETE | `/api/v1/roles/:id` | `roles:destroy` | Eliminar rol |
| POST | `/api/v1/roles/:id/assign_permission` | `roles:update` | Asignar permiso a rol |
| DELETE | `/api/v1/roles/:id/revoke_permission` | `roles:update` | Revocar permiso de rol |
| GET | `/api/v1/users` | `users:read` | Listar usuarios |
| GET | `/api/v1/users/:id` | `users:read` | Ver usuario |
| PATCH | `/api/v1/users/:id` | `users:update` | Actualizar usuario |
| DELETE | `/api/v1/users/:id` | `users:destroy` | Eliminar usuario |
| POST | `/api/v1/users/:id/assign_role` | `users:assign_role` | Asignar rol a usuario |
| DELETE | `/api/v1/users/:id/revoke_role` | `users:revoke_role` | Revocar rol de usuario |

---

## Seeds obligatorios

El agente debe crear estos datos en `db/seeds.rb` en este orden exacto:

```ruby
# 1. Permisos — todos los recursos del sistema
resources = %w[users roles permissions forms]
actions   = %w[read create update destroy manage]

resources.each do |resource|
  actions.each do |action|
    next if action == 'manage' && resource != 'users' # manage solo para users
    Permission.find_or_create_by!(resource: resource, action: action) do |p|
      p.description = "Puede #{action} #{resource}"
    end
  end
end

# 2. Roles base
admin_role = Role.find_or_create_by!(slug: 'admin') do |r|
  r.name        = 'Administrador'
  r.description = 'Acceso completo al sistema'
end

editor_role = Role.find_or_create_by!(slug: 'editor') do |r|
  r.name        = 'Editor'
  r.description = 'Puede gestionar contenido pero no usuarios ni roles'
end

viewer_role = Role.find_or_create_by!(slug: 'viewer') do |r|
  r.name        = 'Viewer'
  r.description = 'Solo lectura'
end

# 3. Asignar permisos a roles
admin_permissions  = Permission.all
editor_permissions = Permission.where(resource: 'forms')
viewer_permissions = Permission.where(action: 'read')

admin_role.permissions  = admin_permissions
editor_role.permissions = editor_permissions
viewer_role.permissions = viewer_permissions

# 4. Super admin user
super_admin = User.find_or_create_by!(email: 'superadmin@boilerplate.dev') do |u|
  u.password    = 'Admin1234!'
  u.name        = 'Super Admin'
  u.super_admin = true
end

# 5. Usuario admin de prueba
admin_user = User.find_or_create_by!(email: 'admin@boilerplate.dev') do |u|
  u.password    = 'Admin1234!'
  u.name        = 'Admin User'
  u.super_admin = false
end
UserRole.find_or_create_by!(user: admin_user, role: admin_role)

# 6. Usuario viewer de prueba
viewer_user = User.find_or_create_by!(email: 'viewer@boilerplate.dev') do |u|
  u.password    = 'Viewer1234!'
  u.name        = 'Viewer User'
  u.super_admin = false
end
UserRole.find_or_create_by!(user: viewer_user, role: viewer_role)
```

---

## Specs requeridos

### Factories

#### spec/factories/roles.rb

```ruby
FactoryBot.define do
  factory :role do
    name        { Faker::Job.title }
    slug        { name.downcase.gsub(/\s+/, '-') }
    description { Faker::Lorem.sentence }
    active      { true }

    trait :admin do
      name { 'Administrador' }
      slug { 'admin' }
    end

    trait :viewer do
      name { 'Viewer' }
      slug { 'viewer' }
    end
  end
end
```

#### spec/factories/permissions.rb

```ruby
FactoryBot.define do
  factory :permission do
    resource { %w[users roles forms].sample }
    action   { %w[read create update destroy].sample }

    trait :users_read do
      resource { 'users' }
      action   { 'read' }
    end

    trait :roles_create do
      resource { 'roles' }
      action   { 'create' }
    end
  end
end
```

### Tests mínimos requeridos

El agente debe crear specs para:

- `spec/domains/authorization/interactors/assign_role_to_user_spec.rb`
  - asigna el rol correctamente
  - lanza error si el rol no existe
  - es idempotente (segunda asignación no duplica)

- `spec/domains/authorization/interactors/fetch_user_permissions_spec.rb`
  - retorna array de strings `resource:action`
  - retorna array vacío si el usuario no tiene roles
  - no incluye permisos de roles expirados

- `spec/domains/authorization/policies/user_policy_spec.rb`
  - super_admin puede todo
  - usuario con permiso `users:read` puede index? y show?
  - usuario sin permisos no puede nada

- `spec/requests/api/v1/roles_spec.rb`
  - GET /roles retorna 200 con permiso correcto
  - GET /roles retorna 403 sin permiso
  - GET /roles retorna 401 sin token

---

## Caché de permisos — nota para el agente

`FetchUserPermissions` hace una query a la BD en cada llamada.
En esta versión del boilerplate el caché es el JWT (los permisos viajan en el token).
No implementar caché adicional en Redis por ahora — eso es una extensión documentada en el README del dominio.
El README del dominio debe mencionar esta decisión y documentar cómo extenderlo.

---

## Reglas — lo que el agente NO debe hacer

- NO usar `current_user.admin?` ni enums de rol en `User`. Los roles viven en la tabla `roles`.
- NO llamar a `Permission.all` ni a modelos AR directamente desde políticas. Siempre via interactor.
- NO cachear permisos en variables de instancia del controller. El JWT es el caché.
- NO crear un endpoint `/api/v1/permissions` de escritura — los permisos son datos de sistema, se crean en seeds.
- NO usar `before_action :authorize!` genérico en el controller base. Cada acción autoriza explícitamente con `authorize @record`.

---

## Definición de done — este dominio

- `rails db:migrate` incluye las 4 tablas nuevas sin errores
- `rails db:seed` crea los 3 roles, todos los permisos, y los 3 usuarios de prueba
- `bundle exec rspec spec/domains/authorization/` pasa al 100%
- `bundle exec rspec spec/requests/api/v1/roles_spec.rb` pasa al 100%
- Un request sin token a `/api/v1/roles` retorna 401
- Un request con token de `viewer@boilerplate.dev` a `POST /api/v1/roles` retorna 403
- Un request con token de `admin@boilerplate.dev` a `GET /api/v1/roles` retorna 200
