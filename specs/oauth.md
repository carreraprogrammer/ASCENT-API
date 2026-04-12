# oauth.md — boilerplate-rails-api

Dominio: `auth`
Responsabilidad: autenticación con Google OAuth 2.0 como método alternativo al registro con email/password.
Leer `architecture.md` y `auth.md` antes de implementar.

---

## Gems requeridas

Agregar al Gemfile:

```ruby
gem 'omniauth-google-oauth2'
gem 'omniauth-rails_csrf_protection'
```

Ejecutar `bundle install` después de modificar el Gemfile.

---

## Variables de entorno

Agregar a `.env.example`:

```
GOOGLE_CLIENT_ID=your_google_client_id_here
GOOGLE_CLIENT_SECRET=your_google_client_secret_here
```

Agregar a `docker-compose.yml` bajo el servicio web:

```yaml
environment:
  GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
  GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
```

El agente NO debe hardcodear estos valores. Si no están definidos, el initializer debe fallar con un mensaje claro.

---

## Migración

Agregar en una migración nueva — no modificar migraciones existentes:

```ruby
# db/migrate/008_add_oauth_to_users.rb
class AddOauthToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :google_uid,    :string, null: true
    add_column :users, :avatar_url,    :string, null: true
    add_column :users, :auth_provider, :string, null: true  # 'google' | nil

    add_index :users, :google_uid, unique: true, where: 'google_uid IS NOT NULL'
  end
end
```

### Modificación al modelo User

Agregar al modelo `app/models/user.rb`:

```ruby
# La contraseña es opcional para usuarios OAuth
validates :encrypted_password, presence: true, unless: :oauth_user?

def oauth_user?
  auth_provider.present?
end
```

---

## Initializer OmniAuth

Crear `config/initializers/omniauth.rb`:

```ruby
OmniAuth.config.logger = Rails.logger

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV.fetch('GOOGLE_CLIENT_ID') { raise 'GOOGLE_CLIENT_ID is not set' },
    ENV.fetch('GOOGLE_CLIENT_SECRET') { raise 'GOOGLE_CLIENT_SECRET is not set' },
    {
      scope: 'email,profile',
      prompt: 'select_account',
      image_aspect_ratio: 'square',
      image_size: 200
    }
end

OmniAuth.config.allowed_request_methods = [:post]
OmniAuth.config.silence_get_warning = true
```

---

## Dominio Auth — extensiones

### Entity User — agregar campos

Modificar `app/domains/auth/entities/user.rb` para incluir los nuevos campos:

```ruby
module Auth
  module Entities
    class User
      attr_reader :id, :email, :name, :encrypted_password,
                  :refresh_token_hash, :refresh_token_expires_at,
                  :confirmed_at, :super_admin,
                  :google_uid, :avatar_url, :auth_provider  # nuevos

      def initialize(
        id:, email:, name:, encrypted_password: nil,
        refresh_token_hash: nil, refresh_token_expires_at: nil,
        confirmed_at: nil, super_admin: false,
        google_uid: nil, avatar_url: nil, auth_provider: nil
      )
        @id                       = id
        @email                    = email
        @name                     = name
        @encrypted_password       = encrypted_password
        @refresh_token_hash       = refresh_token_hash
        @refresh_token_expires_at = refresh_token_expires_at
        @confirmed_at             = confirmed_at
        @super_admin              = super_admin
        @google_uid               = google_uid
        @avatar_url               = avatar_url
        @auth_provider            = auth_provider
      end

      def oauth_user?
        auth_provider.present?
      end
    end
  end
end
```

### Repository — agregar método find_or_create_from_google

Agregar a `app/domains/auth/repositories/user_repository.rb`:

```ruby
def find_by_google_uid(google_uid)
  record = ::User.find_by(google_uid: google_uid)
  record ? map_to_entity(record) : nil
end

def find_or_create_from_google(google_uid:, email:, name:, avatar_url:)
  record = ::User.find_by(google_uid: google_uid)

  unless record
    # Si ya existe un usuario con ese email, vincular la cuenta
    record = ::User.find_by(email: email)

    if record
      record.update!(
        google_uid:    google_uid,
        avatar_url:    avatar_url,
        auth_provider: 'google'
      )
    else
      record = ::User.create!(
        email:         email,
        name:          name,
        google_uid:    google_uid,
        avatar_url:    avatar_url,
        auth_provider: 'google',
        confirmed_at:  Time.current  # Google ya verificó el email
      )
    end
  end

  map_to_entity(record)
end
```

### Interactor — LoginWithGoogle

Crear `app/domains/auth/interactors/login_with_google.rb`:

```ruby
module Auth
  module Interactors
    class LoginWithGoogle
      def initialize(
        user_repo: Repositories::UserRepository.new
      )
        @user_repo = user_repo
      end

      def call(auth_hash:)
        google_uid  = auth_hash.uid
        email       = auth_hash.info.email
        name        = auth_hash.info.name
        avatar_url  = auth_hash.info.image

        raise Auth::Errors::InvalidEmail, 'Google no proporcionó un email' if email.blank?

        user = @user_repo.find_or_create_from_google(
          google_uid: google_uid,
          email:      email,
          name:       name,
          avatar_url: avatar_url
        )

        user
      end
    end
  end
end
```

---

## Controlador OAuth

Crear `app/controllers/api/v1/oauth_controller.rb`:

```ruby
module Api
  module V1
    class OauthController < ActionController::API
      # Este controller NO hereda de ApplicationController
      # porque el flujo OAuth no lleva JWT — es el inicio de la sesión

      def google_callback
        auth_hash = request.env['omniauth.auth']

        unless auth_hash
          return redirect_to_frontend_with_error('google_auth_failed')
        end

        user = Auth::Interactors::LoginWithGoogle.new.call(auth_hash: auth_hash)

        permissions    = Authorization::Interactors::FetchUserPermissions
                           .new.call(user_id: user.id)
        access_token   = JwtService.encode(user: user, permissions: permissions)
        refresh_token  = Auth::Interactors::RefreshToken::Generator.call(user_id: user.id)

        redirect_to_frontend_with_tokens(access_token: access_token, refresh_token: refresh_token)

      rescue Auth::Errors::InvalidEmail => e
        redirect_to_frontend_with_error('invalid_email')
      rescue StandardError => e
        Rails.logger.error("OAuth error: #{e.message}")
        redirect_to_frontend_with_error('server_error')
      end

      def failure
        redirect_to_frontend_with_error(params[:message] || 'oauth_failed')
      end

      private

      def redirect_to_frontend_with_tokens(access_token:, refresh_token:)
        frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
        redirect_to "#{frontend_url}/auth/callback?access_token=#{access_token}&refresh_token=#{refresh_token}",
                    allow_other_host: true
      end

      def redirect_to_frontend_with_error(error_code)
        frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
        redirect_to "#{frontend_url}/auth/callback?error=#{error_code}",
                    allow_other_host: true
      end
    end
  end
end
```

---

## Rutas

Agregar a `config/routes.rb`:

```ruby
# OAuth — fuera del namespace api/v1 porque OmniAuth maneja sus propias rutas
get  '/auth/google_oauth2/callback', to: 'api/v1/oauth#google_callback'
get  '/auth/failure',                to: 'api/v1/oauth#failure'

# El inicio del flujo lo maneja OmniAuth automáticamente:
# POST /auth/google_oauth2 → redirige a Google
```

---

## Presenter — actualizar AuthPresenter

Agregar `avatar_url` y `auth_provider` a la respuesta del presenter existente:

```ruby
# En app/domains/auth/presenters/auth_presenter.rb
# Agregar dentro de attributes:
avatar_url:    entity.avatar_url,
auth_provider: entity.auth_provider,
```

---

## Specs requeridos

### spec/domains/auth/interactors/login_with_google_spec.rb

```ruby
RSpec.describe Auth::Interactors::LoginWithGoogle do
  let(:user_repo) { instance_double(Auth::Repositories::UserRepository) }
  let(:interactor) { described_class.new(user_repo: user_repo) }

  let(:auth_hash) do
    OmniAuth::AuthHash.new({
      uid: 'google-uid-123',
      info: {
        email: 'user@gmail.com',
        name:  'Test User',
        image: 'https://example.com/avatar.jpg'
      }
    })
  end

  describe '#call' do
    it 'crea o encuentra el usuario con los datos de Google' do
      user = build(:user, google_uid: 'google-uid-123')
      allow(user_repo).to receive(:find_or_create_from_google).and_return(user)

      result = interactor.call(auth_hash: auth_hash)

      expect(result).to eq(user)
      expect(user_repo).to have_received(:find_or_create_from_google).with(
        google_uid: 'google-uid-123',
        email:      'user@gmail.com',
        name:       'Test User',
        avatar_url: 'https://example.com/avatar.jpg'
      )
    end

    it 'lanza Auth::Errors::InvalidEmail si Google no provee email' do
      auth_hash_sin_email = OmniAuth::AuthHash.new({
        uid: 'google-uid-123',
        info: { email: nil, name: 'Test', image: nil }
      })

      expect {
        interactor.call(auth_hash: auth_hash_sin_email)
      }.to raise_error(Auth::Errors::InvalidEmail)
    end
  end
end
```

---

## Definición de done — este spec

- `rails db:migrate` incluye la migración 008 sin errores
- Un usuario creado vía OAuth no requiere `encrypted_password`
- `GET /auth/google_oauth2` inicia el flujo de redirect a Google
- `GET /auth/google_oauth2/callback` con auth válida redirige al frontend con tokens en query params
- `GET /auth/google_oauth2/callback` con auth fallida redirige al frontend con `?error=google_auth_failed`
- `bundle exec rspec spec/domains/auth/interactors/login_with_google_spec.rb` pasa al 100%
- Un usuario que se registra con Google y luego intenta login con email/password recibe error descriptivo
