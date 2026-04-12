# forms.md
<!-- domain: forms | repo: boilerplate-rails-api | version: 1.0 -->
<!-- depends on: architecture.md, auth.md, roles-permissions.md must be implemented first -->

## Purpose

This spec defines the `forms` domain. This domain implements the Schema-Driven UI (SDUI) pattern — the backend defines the structure, validation rules, and submission target of any form. The frontend receives this schema and builds the UI dynamically without hardcoding form fields.

## What this domain does

- Store form schemas in the database with all field definitions
- Serve schema JSON via a public read endpoint (no auth required for reading)
- Protect create/update/destroy endpoints with `form_schemas:create/update/destroy` permissions
- Validate that schemas are structurally correct before saving
- Provide seed data with three ready-to-use schemas

## What this domain does NOT do

- Process form submissions (each domain handles its own endpoint)
- Validate submitted field values (that is the frontend's job, guided by the schema)
- Render any HTML

---

## Database — Migration

```ruby
# db/migrate/006_create_form_schemas.rb

class CreateFormSchemas < ActiveRecord::Migration[8.0]
  def change
    create_table :form_schemas do |t|
      t.string  :slug,            null: false   # URL-friendly identifier, used as param
      t.string  :title,           null: false
      t.string  :submit_label,    null: false, default: "Submit"
      t.string  :submit_endpoint, null: false   # e.g. /api/v1/auth/login
      t.string  :submit_method,   null: false, default: "POST"
      t.json    :fields,          null: false   # array of FieldSchema objects
      t.boolean :active,          null: false, default: true

      t.timestamps
    end

    add_index :form_schemas, :slug,   unique: true
    add_index :form_schemas, :active
  end
end
```

---

## Field Schema Structure

Each element in the `fields` JSON array must conform to this structure. The backend validates this on save.

```json
{
  "name":          "email",
  "label":         "Email address",
  "type":          "email",
  "placeholder":   "you@example.com",
  "required":      true,
  "order":         1,
  "validations": {
    "format":      "email",
    "max_length":  255
  }
}
```

### Supported field types

```
text | email | password | number | tel | url
textarea | select | checkbox | radio
date | datetime-local | hidden
```

### Full FieldSchema definition

```
name          string   required — snake_case, unique within form, maps to submitted param key
label         string   required — display label shown to user
type          string   required — one of the supported types above
placeholder   string   optional
required      boolean  required
order         integer  required — fields render in ascending order
validations   object   optional:
  format        string  — "email" | "url" | "phone"
  min_length    integer
  max_length    integer
  pattern       string  — regex pattern as string
options       array    required if type is "select" or "radio"
  each option:
    label  string  required
    value  string  required
rows          integer  optional — only for textarea, default 3
default_value string   optional — pre-filled value
```

---

## Entity

```ruby
# app/domains/forms/entities/form_schema.rb

module Forms
  module Entities
    class FormSchema
      VALID_TYPES   = %w[text email password number tel url textarea select checkbox radio date datetime-local hidden].freeze
      VALID_METHODS = %w[POST PUT PATCH].freeze

      attr_reader :id, :slug, :title, :submit_label, :submit_endpoint,
                  :submit_method, :fields, :active, :created_at, :updated_at

      def initialize(attrs = {})
        @id              = attrs[:id]
        @slug            = attrs[:slug]
        @title           = attrs[:title]
        @submit_label    = attrs[:submit_label]
        @submit_endpoint = attrs[:submit_endpoint]
        @submit_method   = attrs[:submit_method]
        @fields          = attrs[:fields] || []
        @active          = attrs[:active]
        @created_at      = attrs[:created_at]
        @updated_at      = attrs[:updated_at]
      end

      def active? = @active == true

      def valid?
        errors.empty?
      end

      def errors
        errs = []
        errs << "slug is required" if slug.blank?
        errs << "title is required" if title.blank?
        errs << "submit_endpoint is required" if submit_endpoint.blank?
        errs << "submit_method must be POST, PUT, or PATCH" unless VALID_METHODS.include?(submit_method)
        errs << "fields must be an array" unless fields.is_a?(Array)
        errs << "fields cannot be empty" if fields.empty?
        fields.each_with_index do |field, i|
          errs << "field[#{i}] name is required" if field["name"].blank?
          errs << "field[#{i}] label is required" if field["label"].blank?
          errs << "field[#{i}] type '#{field["type"]}' is not supported" unless VALID_TYPES.include?(field["type"])
          errs << "field[#{i}] order is required" if field["order"].nil?
          if %w[select radio].include?(field["type"]) && Array(field["options"]).empty?
            errs << "field[#{i}] of type '#{field["type"]}' must have options"
          end
        end
        errs
      end
    end
  end
end
```

---

## Repository

```ruby
# app/domains/forms/repositories/form_schema_repository.rb

module Forms
  module Repositories
    class FormSchemaRepository
      def all_active
        ::FormSchema.where(active: true).order(:slug).map { |r| map_to_entity(r) }
      end

      def find_by_slug(slug)
        record = ::FormSchema.find_by(slug: slug, active: true)
        return nil if record.nil?

        map_to_entity(record)
      end

      def create(attrs)
        record = ::FormSchema.create!(
          slug:            attrs[:slug],
          title:           attrs[:title],
          submit_label:    attrs[:submit_label] || "Submit",
          submit_endpoint: attrs[:submit_endpoint],
          submit_method:   attrs[:submit_method] || "POST",
          fields:          attrs[:fields],
          active:          attrs.fetch(:active, true)
        )
        map_to_entity(record)
      end

      def update(slug, attrs)
        record = ::FormSchema.find_by!(slug: slug)
        record.update!(attrs.slice(:title, :submit_label, :submit_endpoint, :submit_method, :fields, :active))
        map_to_entity(record)
      end

      def deactivate(slug)
        ::FormSchema.find_by!(slug: slug).update!(active: false)
      end

      private

      def map_to_entity(record)
        Forms::Entities::FormSchema.new(
          id:              record.id,
          slug:            record.slug,
          title:           record.title,
          submit_label:    record.submit_label,
          submit_endpoint: record.submit_endpoint,
          submit_method:   record.submit_method,
          fields:          record.fields,
          active:          record.active,
          created_at:      record.created_at,
          updated_at:      record.updated_at
        )
      end
    end
  end
end
```

---

## Interactors

```ruby
# app/domains/forms/interactors/fetch_form_schema.rb

module Forms
  module Interactors
    class FetchFormSchema
      def initialize(repo: Forms::Repositories::FormSchemaRepository.new)
        @repo = repo
      end

      def call(slug:)
        schema = @repo.find_by_slug(slug)
        raise ActiveRecord::RecordNotFound, "Form schema '#{slug}' not found" if schema.nil?

        schema
      end
    end
  end
end
```

```ruby
# app/domains/forms/interactors/create_form_schema.rb

module Forms
  module Interactors
    class CreateFormSchema
      def initialize(repo: Forms::Repositories::FormSchemaRepository.new)
        @repo = repo
      end

      def call(attrs)
        schema = Forms::Entities::FormSchema.new(attrs)
        raise Forms::Errors::InvalidSchema, schema.errors.join(", ") unless schema.valid?

        @repo.create(attrs)
      end
    end
  end
end
```

---

## Domain Errors

```ruby
# app/domains/forms/errors.rb

module Forms
  module Errors
    class InvalidSchema < StandardError; end
  end
end
```

---

## Presenter

```ruby
# app/domains/forms/presenters/form_schema_presenter.rb

module Forms
  module Presenters
    class FormSchemaPresenter
      def self.single(schema)
        {
          data: serialize(schema)
        }
      end

      def self.collection(schemas)
        {
          data: schemas.map { |s| serialize(s) },
          meta: { total: schemas.size }
        }
      end

      private_class_method def self.serialize(schema)
        {
          id:   schema.slug,          # use slug as public ID
          type: "form_schemas",
          attributes: {
            slug:            schema.slug,
            title:           schema.title,
            submit_label:    schema.submit_label,
            submit_endpoint: schema.submit_endpoint,
            submit_method:   schema.submit_method,
            fields:          schema.fields.sort_by { |f| f["order"].to_i }
          }
        }
      end
    end
  end
end
```

---

## Controller

```ruby
# app/controllers/api/v1/forms_controller.rb

class Api::V1::FormsController < Api::V1::BaseController
  skip_before_action :authenticate_request!, only: [:index, :show]

  def index
    schemas = Forms::Interactors::FetchAllFormSchemas.new.call
    render json: Forms::Presenters::FormSchemaPresenter.collection(schemas)
  end

  def show
    schema = Forms::Interactors::FetchFormSchema.new.call(slug: params[:slug])
    render json: Forms::Presenters::FormSchemaPresenter.single(schema)
  end

  def create
    authorize :form_schema, :create?
    schema = Forms::Interactors::CreateFormSchema.new.call(schema_params)
    render json: Forms::Presenters::FormSchemaPresenter.single(schema), status: :created
  rescue Forms::Errors::InvalidSchema => e
    render json: { errors: [{ status: "422", title: "Invalid Schema", detail: e.message }] },
           status: :unprocessable_entity
  end

  def update
    authorize :form_schema, :update?
    schema = Forms::Interactors::UpdateFormSchema.new.call(params[:slug], schema_params)
    render json: Forms::Presenters::FormSchemaPresenter.single(schema)
  end

  def destroy
    authorize :form_schema, :destroy?
    Forms::Repositories::FormSchemaRepository.new.deactivate(params[:slug])
    head :no_content
  end

  private

  def schema_params
    params.permit(
      :slug, :title, :submit_label, :submit_endpoint, :submit_method, :active,
      fields: [:name, :label, :type, :placeholder, :required, :order, :rows, :default_value,
               validations: [:format, :min_length, :max_length, :pattern],
               options: [:label, :value]]
    ).to_h.deep_symbolize_keys
  end
end
```

---

## ActiveRecord Model

```ruby
# app/models/form_schema.rb

class FormSchema < ApplicationRecord
  validates :slug,            presence: true, uniqueness: true,
                              format: { with: /\A[a-z0-9\-]+\z/, message: "only lowercase letters, numbers, hyphens" }
  validates :title,           presence: true
  validates :submit_endpoint, presence: true
  validates :submit_method,   inclusion: { in: %w[POST PUT PATCH] }
  validates :fields,          presence: true
end
```

---

## Seeds — Three Required Schemas

```ruby
# db/seeds.rb (forms section)

forms = [
  {
    slug:            "login-form",
    title:           "Sign In",
    submit_label:    "Sign In",
    submit_endpoint: "/api/v1/auth/login",
    submit_method:   "POST",
    fields: [
      {
        "name" => "email", "label" => "Email address", "type" => "email",
        "placeholder" => "you@example.com", "required" => true, "order" => 1,
        "validations" => { "format" => "email", "max_length" => 255 }
      },
      {
        "name" => "password", "label" => "Password", "type" => "password",
        "placeholder" => "••••••••", "required" => true, "order" => 2,
        "validations" => { "min_length" => 8 }
      }
    ]
  },
  {
    slug:            "register-form",
    title:           "Create Account",
    submit_label:    "Create Account",
    submit_endpoint: "/api/v1/auth/register",
    submit_method:   "POST",
    fields: [
      {
        "name" => "name", "label" => "Full name", "type" => "text",
        "placeholder" => "Your name", "required" => true, "order" => 1,
        "validations" => { "min_length" => 2, "max_length" => 100 }
      },
      {
        "name" => "email", "label" => "Email address", "type" => "email",
        "placeholder" => "you@example.com", "required" => true, "order" => 2,
        "validations" => { "format" => "email", "max_length" => 255 }
      },
      {
        "name" => "password", "label" => "Password", "type" => "password",
        "placeholder" => "Min. 8 characters", "required" => true, "order" => 3,
        "validations" => { "min_length" => 8 }
      },
      {
        "name" => "password_confirmation", "label" => "Confirm password",
        "type" => "password", "placeholder" => "Repeat your password",
        "required" => true, "order" => 4, "validations" => { "min_length" => 8 }
      }
    ]
  },
  {
    slug:            "profile-form",
    title:           "Edit Profile",
    submit_label:    "Save Changes",
    submit_endpoint: "/api/v1/auth/me",
    submit_method:   "PATCH",
    fields: [
      {
        "name" => "name", "label" => "Full name", "type" => "text",
        "placeholder" => "Your name", "required" => true, "order" => 1,
        "validations" => { "min_length" => 2, "max_length" => 100 }
      },
      {
        "name" => "bio", "label" => "Bio", "type" => "textarea",
        "placeholder" => "Tell us about yourself", "required" => false,
        "order" => 2, "rows" => 4, "validations" => { "max_length" => 500 }
      },
      {
        "name" => "phone", "label" => "Phone number", "type" => "tel",
        "placeholder" => "+57 300 000 0000", "required" => false, "order" => 3,
        "validations" => { "format" => "phone" }
      },
      {
        "name" => "birth_date", "label" => "Date of birth", "type" => "date",
        "required" => false, "order" => 4
      }
    ]
  }
]

forms.each do |attrs|
  FormSchema.find_or_create_by!(slug: attrs[:slug]) do |f|
    f.title           = attrs[:title]
    f.submit_label    = attrs[:submit_label]
    f.submit_endpoint = attrs[:submit_endpoint]
    f.submit_method   = attrs[:submit_method]
    f.fields          = attrs[:fields]
    f.active          = true
  end
end

puts "Seeded: #{FormSchema.count} form schemas"
```

---

## RSpec — Factory and Specs

```ruby
# spec/factories/form_schemas.rb

FactoryBot.define do
  factory :form_schema do
    slug            { "test-form-#{SecureRandom.hex(4)}" }
    title           { "Test Form" }
    submit_label    { "Submit" }
    submit_endpoint { "/api/v1/auth/login" }
    submit_method   { "POST" }
    active          { true }
    fields do
      [
        { "name" => "email", "label" => "Email", "type" => "email",
          "required" => true, "order" => 1 }
      ]
    end
  end
end
```

```ruby
# spec/requests/api/v1/forms_spec.rb

RSpec.describe "Forms API" do
  let!(:schema) { create(:form_schema, slug: "login-form") }

  describe "GET /api/v1/form_schemas/:slug" do
    it "returns the schema without authentication" do
      get "/api/v1/form_schemas/login-form"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "id")).to eq("login-form")
      expect(json.dig("data", "type")).to eq("form_schemas")
      expect(json.dig("data", "attributes", "fields")).to be_an(Array)
    end

    it "returns 404 for unknown slug" do
      get "/api/v1/form_schemas/nonexistent"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/form_schemas" do
    it "returns 401 without token" do
      post "/api/v1/form_schemas", params: {}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

---

## Definition of Done — Forms Domain

- [ ] Migration runs without errors
- [ ] `db:seed` creates exactly 3 schemas (`login-form`, `register-form`, `profile-form`) without errors
- [ ] `GET /api/v1/form_schemas/login-form` returns correct JSON:API structure with no authentication
- [ ] `GET /api/v1/form_schemas/nonexistent` returns 404
- [ ] Fields in response are sorted by `order` ascending
- [ ] `FormSchema` entity `errors` method catches all invalid field types
- [ ] `POST /api/v1/form_schemas` returns 401 without token, 403 without `form_schemas:create`
- [ ] `POST /api/v1/form_schemas` returns 201 with valid payload and admin token
- [ ] `DELETE /api/v1/form_schemas/:slug` sets `active: false`, does not destroy record
- [ ] RSpec tests pass
- [ ] RuboCop returns zero offenses
