# auth.md
<!-- domain: auth | repo: boilerplate-rails-api | version: 1.0 -->
<!-- depends on: architecture.md must be implemented first -->

## Purpose

This spec defines the `auth` domain. This domain is responsible for user registration, login, logout, and JWT token lifecycle management. It does NOT handle roles or permissions — that is the `authorization` domain.

## What this domain does

- Register a new user with email + password
- Authenticate a user and issue an access token + refresh token
- Rotate refresh tokens on every use
- Detect stolen refresh tokens and invalidate all sessions
- Decode and validate access tokens for the base controller
- Return the current authenticated user's profile

## What this domain does NOT do

- Assign roles (authorization domain)
- Check permissions (authorization domain + Pundit)
- Send emails (future extension point via events)
- OAuth / social login (future extension point)

---

## Database — Migration

```ruby
# db/migrate/001_create_users.rb

class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :email,                    null: false
      t.string  :encrypted_password,       null: false
      t.string  :name,                     null: false
      t.string  :refresh_token_hash,       null: true   # NULL means no active session
      t.datetime :refresh_token_expires_at, null: true
      t.datetime :confirmed_at,            null: true   # NULL means unconfirmed

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :refresh_token_hash
  end
end
```

---

## Value Objects

### Auth::ValueObjects::Email

```ruby
# app/domains/auth/value_objects/email.rb

module Auth
  module ValueObjects
    class Email
      VALID_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      attr_reader :value

      def initialize(raw_value)
        normalized = raw_value.to_s.strip.downcase
        raise Auth::Errors::InvalidEmail, "Invalid email format: #{raw_value}" unless normalized.match?(VALID_FORMAT)
        raise Auth::Errors::InvalidEmail, "Email exceeds 255 characters" if normalized.length > 255

        @value = normalized
      end

      def to_s = @value
      def ==(other) = other.is_a?(Email) && value == other.value
    end
  end
end
```

### Auth::ValueObjects::Password

```ruby
# app/domains/auth/value_objects/password.rb

module Auth
  module ValueObjects
    class Password
      MIN_LENGTH = 8
      REQUIRES_NUMBER = /\d/
      REQUIRES_UPPERCASE = /[A-Z]/

      attr_reader :raw

      def initialize(raw_value)
        errors = []
        errors << "Password must be at least #{MIN_LENGTH} characters" if raw_value.to_s.length < MIN_LENGTH
        errors << "Password must contain at least one number" unless raw_value.to_s.match?(REQUIRES_NUMBER)
        errors << "Password must contain at least one uppercase letter" unless raw_value.to_s.match?(REQUIRES_UPPERCASE)

        raise Auth::Errors::WeakPassword, errors.join(". ") if errors.any?

        @raw = raw_value
      end
    end
  end
end
```

---

## Domain Errors

```ruby
# app/domains/auth/errors.rb

module Auth
  module Errors
    class InvalidEmail    < StandardError; end
    class WeakPassword    < StandardError; end
    class InvalidToken    < StandardError; end
    class ExpiredToken    < StandardError; end
    class InvalidCredentials < StandardError; end
    class TokenReuse      < StandardError; end  # stolen token detected
  end
end
```

---

## Entity

### Auth::Entities::User

```ruby
# app/domains/auth/entities/user.rb

module Auth
  module Entities
    class User
      attr_reader :id, :email, :name, :encrypted_password,
                  :refresh_token_hash, :refresh_token_expires_at,
                  :confirmed_at, :created_at

      def initialize(attrs = {})
        @id                       = attrs[:id]
        @email                    = attrs[:email]
        @name                     = attrs[:name]
        @encrypted_password       = attrs[:encrypted_password]
        @refresh_token_hash       = attrs[:refresh_token_hash]
        @refresh_token_expires_at = attrs[:refresh_token_expires_at]
        @confirmed_at             = attrs[:confirmed_at]
        @created_at               = attrs[:created_at]
      end

      def confirmed? = !confirmed_at.nil?

      def refresh_token_valid?(raw_token)
        return false if refresh_token_hash.nil?
        return false if refresh_token_expires_at.nil? || refresh_token_expires_at < Time.current

        BCrypt::Password.new(refresh_token_hash) == raw_token
      end
    end
  end
end
```

---

## Repository

```ruby
# app/domains/auth/repositories/user_repository.rb

module Auth
  module Repositories
    class UserRepository
      def find_by_email(email)
        record = ::User.find_by(email: email.to_s)
        return nil if record.nil?

        map_to_entity(record)
      end

      def find_by_id(id)
        record = ::User.find_by(id: id)
        return nil if record.nil?

        map_to_entity(record)
      end

      def create(email:, name:, encrypted_password:)
        record = ::User.create!(
          email: email.to_s,
          name: name,
          encrypted_password: encrypted_password
        )
        map_to_entity(record)
      end

      def save_refresh_token(user_id:, token_hash:, expires_at:)
        ::User.find(user_id).update!(
          refresh_token_hash: token_hash,
          refresh_token_expires_at: expires_at
        )
      end

      def invalidate_refresh_token(user_id:)
        ::User.find(user_id).update!(
          refresh_token_hash: nil,
          refresh_token_expires_at: nil
        )
      end

      private

      def map_to_entity(record)
        Auth::Entities::User.new(
          id:                       record.id,
          email:                    record.email,
          name:                     record.name,
          encrypted_password:       record.encrypted_password,
          refresh_token_hash:       record.refresh_token_hash,
          refresh_token_expires_at: record.refresh_token_expires_at,
          confirmed_at:             record.confirmed_at,
          created_at:               record.created_at
        )
      end
    end
  end
end
```

---

## JwtService

```ruby
# app/services/jwt_service.rb

class JwtService
  ALGORITHM = "HS256"

  def self.encode_access_token(user_id:, email:)
    payload = {
      user_id: user_id,
      email: email,
      jti: SecureRandom.uuid,
      exp: Time.current.to_i + ENV.fetch("JWT_ACCESS_EXPIRY", 900).to_i,
      type: "access"
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.encode_refresh_token
    SecureRandom.urlsafe_base64(64)
  end

  def self.decode_access_token(token)
    decoded = JWT.decode(token, secret, true, algorithm: ALGORITHM).first
    raise Auth::Errors::InvalidToken unless decoded["type"] == "access"

    decoded
  rescue JWT::ExpiredSignature
    raise Auth::Errors::ExpiredToken
  rescue JWT::DecodeError
    raise Auth::Errors::InvalidToken
  end

  def self.secret
    ENV.fetch("JWT_SECRET") { raise "JWT_SECRET environment variable is not set" }
  end
end
```

---

## Interactors

### Auth::Interactors::RegisterUser

```ruby
# app/domains/auth/interactors/register_user.rb

module Auth
  module Interactors
    class RegisterUser
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end

      def call(email:, password:, name:)
        email_vo    = Auth::ValueObjects::Email.new(email)
        password_vo = Auth::ValueObjects::Password.new(password)

        raise Auth::Errors::InvalidEmail, "Email already taken" if @repo.find_by_email(email_vo)

        encrypted = BCrypt::Password.create(password_vo.raw)
        user      = @repo.create(email: email_vo, name: name, encrypted_password: encrypted)

        tokens    = issue_tokens(user)

        EventBus.publish(Auth::Events::UserRegistered.new(user_id: user.id, email: user.email))

        { user: user, **tokens }
      end

      private

      def issue_tokens(user)
        raw_refresh   = JwtService.encode_refresh_token
        refresh_hash  = BCrypt::Password.create(raw_refresh)
        expires_at    = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds

        @repo.save_refresh_token(
          user_id:    user.id,
          token_hash: refresh_hash,
          expires_at: expires_at
        )

        {
          access_token:  JwtService.encode_access_token(user_id: user.id, email: user.email),
          refresh_token: raw_refresh
        }
      end
    end
  end
end
```

### Auth::Interactors::LoginUser

```ruby
# app/domains/auth/interactors/login_user.rb

module Auth
  module Interactors
    class LoginUser
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end

      def call(email:, password:)
        email_vo = Auth::ValueObjects::Email.new(email)
        user     = @repo.find_by_email(email_vo)

        raise Auth::Errors::InvalidCredentials unless user
        raise Auth::Errors::InvalidCredentials unless BCrypt::Password.new(user.encrypted_password) == password

        raw_refresh  = JwtService.encode_refresh_token
        refresh_hash = BCrypt::Password.create(raw_refresh)
        expires_at   = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds

        @repo.save_refresh_token(user_id: user.id, token_hash: refresh_hash, expires_at: expires_at)

        {
          user:          user,
          access_token:  JwtService.encode_access_token(user_id: user.id, email: user.email),
          refresh_token: raw_refresh
        }
      end
    end
  end
end
```

### Auth::Interactors::RefreshToken

```ruby
# app/domains/auth/interactors/refresh_token.rb

module Auth
  module Interactors
    class RefreshToken
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end

      def call(user_id:, raw_refresh_token:)
        user = @repo.find_by_id(user_id)
        raise Auth::Errors::InvalidToken unless user

        unless user.refresh_token_valid?(raw_refresh_token)
          # Token reuse detected — stolen token. Invalidate all sessions.
          @repo.invalidate_refresh_token(user_id: user.id)
          raise Auth::Errors::TokenReuse
        end

        new_raw_refresh  = JwtService.encode_refresh_token
        new_refresh_hash = BCrypt::Password.create(new_raw_refresh)
        expires_at       = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds

        @repo.save_refresh_token(user_id: user.id, token_hash: new_refresh_hash, expires_at: expires_at)

        {
          access_token:  JwtService.encode_access_token(user_id: user.id, email: user.email),
          refresh_token: new_raw_refresh
        }
      end
    end
  end
end
```

---

## Presenter

```ruby
# app/domains/auth/presenters/auth_presenter.rb

module Auth
  module Presenters
    class AuthPresenter
      def self.user_with_tokens(user:, access_token:, refresh_token:)
        {
          data: {
            id:   user.id.to_s,
            type: "users",
            attributes: {
              email:        user.email,
              name:         user.name,
              confirmed:    user.confirmed?,
              created_at:   user.created_at
            }
          },
          meta: {
            access_token:  access_token,
            refresh_token: refresh_token
          }
        }
      end

      def self.user(user)
        {
          data: {
            id:   user.id.to_s,
            type: "users",
            attributes: {
              email:      user.email,
              name:       user.name,
              confirmed:  user.confirmed?,
              created_at: user.created_at
            }
          }
        }
      end

      def self.tokens(access_token:, refresh_token:)
        {
          meta: {
            access_token:  access_token,
            refresh_token: refresh_token
          }
        }
      end
    end
  end
end
```

---

## Domain Event

```ruby
# app/domains/auth/events/user_registered.rb

module Auth
  module Events
    class UserRegistered
      attr_reader :user_id, :email, :occurred_at

      def initialize(user_id:, email:)
        @user_id     = user_id
        @email       = email
        @occurred_at = Time.current
      end
    end
  end
end
```

---

## Controller

```ruby
# app/controllers/api/v1/auth_controller.rb

class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_request!, only: [:register, :login, :refresh]

  def register
    result = Auth::Interactors::RegisterUser.new.call(
      email:    params.require(:email),
      password: params.require(:password),
      name:     params.require(:name)
    )
    render json: Auth::Presenters::AuthPresenter.user_with_tokens(**result), status: :created
  rescue Auth::Errors::InvalidEmail, Auth::Errors::WeakPassword => e
    render_unprocessable(e.message)
  end

  def login
    result = Auth::Interactors::LoginUser.new.call(
      email:    params.require(:email),
      password: params.require(:password)
    )
    render json: Auth::Presenters::AuthPresenter.user_with_tokens(**result)
  rescue Auth::Errors::InvalidCredentials
    render_unauthorized
  end

  def refresh
    result = Auth::Interactors::RefreshToken.new.call(
      user_id:           params.require(:user_id),
      raw_refresh_token: params.require(:refresh_token)
    )
    render json: Auth::Presenters::AuthPresenter.tokens(**result)
  rescue Auth::Errors::TokenReuse, Auth::Errors::InvalidToken
    render_unauthorized
  end

  def logout
    Auth::Repositories::UserRepository.new.invalidate_refresh_token(user_id: current_user.id)
    head :no_content
  end

  def me
    render json: Auth::Presenters::AuthPresenter.user(current_user)
  end

  private

  def render_unprocessable(detail)
    render json: {
      errors: [{ status: "422", title: "Unprocessable Entity", detail: detail }]
    }, status: :unprocessable_entity
  end
end
```

---

## ActiveRecord Model

```ruby
# app/models/user.rb

class User < ApplicationRecord
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  validates :email,                presence: true, uniqueness: true
  validates :encrypted_password,   presence: true
  validates :name,                 presence: true
end
```

---

## RSpec — Factories

```ruby
# spec/factories/users.rb

FactoryBot.define do
  factory :user do
    email               { Faker::Internet.unique.email }
    name                { Faker::Name.full_name }
    encrypted_password  { BCrypt::Password.create("Password1") }
    confirmed_at        { nil }

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :with_refresh_token do
      refresh_token_hash        { BCrypt::Password.create("sample_token") }
      refresh_token_expires_at  { 30.days.from_now }
    end
  end
end
```

---

## RSpec — Specs

### Value Object specs

```ruby
# spec/domains/auth/value_objects/email_spec.rb

RSpec.describe Auth::ValueObjects::Email do
  it "accepts valid email" do
    expect { described_class.new("user@example.com") }.not_to raise_error
  end

  it "normalizes to lowercase" do
    expect(described_class.new("USER@EXAMPLE.COM").value).to eq("user@example.com")
  end

  it "raises InvalidEmail for missing @" do
    expect { described_class.new("notanemail") }.to raise_error(Auth::Errors::InvalidEmail)
  end

  it "raises InvalidEmail for empty string" do
    expect { described_class.new("") }.to raise_error(Auth::Errors::InvalidEmail)
  end
end
```

### Interactor specs (example)

```ruby
# spec/domains/auth/interactors/register_user_spec.rb

RSpec.describe Auth::Interactors::RegisterUser do
  subject(:interactor) { described_class.new }

  let(:valid_params) { { email: "new@example.com", password: "Password1", name: "Daniel" } }

  it "creates a user and returns tokens" do
    result = interactor.call(**valid_params)

    expect(result[:user]).to be_a(Auth::Entities::User)
    expect(result[:access_token]).to be_present
    expect(result[:refresh_token]).to be_present
  end

  it "raises InvalidEmail if email already taken" do
    create(:user, email: "new@example.com")
    expect { interactor.call(**valid_params) }.to raise_error(Auth::Errors::InvalidEmail)
  end

  it "raises WeakPassword if password is too simple" do
    expect { interactor.call(**valid_params.merge(password: "simple")) }
      .to raise_error(Auth::Errors::WeakPassword)
  end
end
```

### Request specs

```ruby
# spec/requests/api/v1/auth_spec.rb

RSpec.describe "POST /api/v1/auth/register" do
  it "returns 201 with user data and tokens" do
    post "/api/v1/auth/register", params: {
      email: "new@example.com", password: "Password1", name: "Daniel"
    }

    expect(response).to have_http_status(:created)
    json = JSON.parse(response.body)
    expect(json.dig("data", "type")).to eq("users")
    expect(json.dig("meta", "access_token")).to be_present
    expect(json.dig("meta", "refresh_token")).to be_present
  end

  it "returns 422 if email already exists" do
    create(:user, email: "existing@example.com")
    post "/api/v1/auth/register", params: {
      email: "existing@example.com", password: "Password1", name: "Daniel"
    }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

---

## Definition of Done — Auth Domain

- [ ] Migration runs without errors
- [ ] `Email` VO raises `InvalidEmail` for all invalid formats
- [ ] `Password` VO raises `WeakPassword` for all weak patterns
- [ ] `RegisterUser` creates user and returns access + refresh token
- [ ] `LoginUser` returns tokens for valid credentials, raises for invalid
- [ ] `RefreshToken` issues new token pair and invalidates previous refresh token
- [ ] `RefreshToken` invalidates ALL sessions when a reused token is detected
- [ ] `POST /api/v1/auth/register` returns 201 with JSON:API body
- [ ] `POST /api/v1/auth/login` returns 200 with JSON:API body
- [ ] `POST /api/v1/auth/refresh` returns 200 with new tokens
- [ ] `DELETE /api/v1/auth/logout` returns 204
- [ ] `GET /api/v1/auth/me` returns current user, 401 if no token
- [ ] All RSpec tests pass
- [ ] RuboCop returns zero offenses
