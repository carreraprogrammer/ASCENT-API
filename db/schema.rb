# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 20260415) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.bigint "owner_user_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "active", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_user_id"], name: "index_accounts_on_owner_user_id"
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
  end

  create_table "agent_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.jsonb "capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_agent_types_on_slug", unique: true
  end

  create_table "budgets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "category_id", null: false
    t.integer "month", null: false
    t.integer "year", null: false
    t.integer "amount_limit", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.index ["account_id"], name: "index_budgets_on_account_id"
    t.index ["category_id"], name: "index_budgets_on_category_id"
    t.index ["user_id", "category_id", "month", "year"], name: "index_budgets_on_user_id_and_category_id_and_month_and_year", unique: true
    t.index ["user_id"], name: "index_budgets_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name", null: false
    t.string "code", null: false
    t.string "category_type", null: false
    t.string "color"
    t.string "icon"
    t.boolean "is_system", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.index ["account_id", "code"], name: "index_categories_on_account_id_and_code"
    t.index ["account_id"], name: "index_categories_on_account_id"
    t.index ["code"], name: "index_categories_on_code"
    t.index ["user_id", "code"], name: "index_categories_on_user_id_and_code"
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "debts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "debt_type", default: "personal_loan", null: false
    t.integer "original_amount", default: 0, null: false
    t.integer "current_balance", default: 0, null: false
    t.integer "monthly_payment", default: 0, null: false
    t.decimal "interest_rate", precision: 5, scale: 2, default: "0.0"
    t.string "status", default: "active", null: false
    t.date "payoff_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "notes"
    t.jsonb "ai_analysis", default: [], null: false
    t.bigint "account_id"
    t.index ["account_id", "status"], name: "index_debts_on_account_id_and_status"
    t.index ["account_id"], name: "index_debts_on_account_id"
    t.index ["user_id", "status"], name: "index_debts_on_user_id_and_status"
    t.index ["user_id"], name: "index_debts_on_user_id"
  end

  create_table "delegations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.bigint "service_account_id", null: false
    t.bigint "agent_type_id", null: false
    t.jsonb "scopes", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "granted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_delegations_on_account_id"
    t.index ["agent_type_id"], name: "index_delegations_on_agent_type_id"
    t.index ["service_account_id"], name: "index_delegations_on_service_account_id"
    t.index ["user_id", "account_id", "service_account_id", "agent_type_id"], name: "index_delegations_on_owner_and_actor_and_type", unique: true
    t.index ["user_id"], name: "index_delegations_on_user_id"
  end

  create_table "financial_contexts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "phase", default: "debt_payoff", null: false
    t.string "strategy", default: "snowball", null: false
    t.integer "reward_pct", default: 5, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.index ["account_id"], name: "index_financial_contexts_on_account_id"
    t.index ["user_id"], name: "index_financial_contexts_on_user_id", unique: true
  end

  create_table "form_schemas", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.string "submit_label", default: "Submit", null: false
    t.string "submit_endpoint", null: false
    t.string "submit_method", default: "POST", null: false
    t.json "fields", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_form_schemas_on_active"
    t.index ["slug"], name: "index_form_schemas_on_slug", unique: true
  end

  create_table "income_sources", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.integer "expected_day_from", null: false
    t.integer "expected_day_to", null: false
    t.integer "expected_amount", default: 0, null: false
    t.boolean "is_variable", default: false, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.index ["account_id", "active"], name: "index_income_sources_on_account_id_and_active"
    t.index ["account_id"], name: "index_income_sources_on_account_id"
    t.index ["user_id", "active"], name: "index_income_sources_on_user_id_and_active"
    t.index ["user_id"], name: "index_income_sources_on_user_id"
  end

  create_table "pending_actions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "action_type", null: false
    t.integer "current_step", default: 0, null: false
    t.integer "total_steps", default: 1, null: false
    t.jsonb "context", default: {}, null: false
    t.string "status", default: "in_progress", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.index ["account_id", "status"], name: "index_pending_actions_on_account_id_and_status"
    t.index ["account_id"], name: "index_pending_actions_on_account_id"
    t.index ["user_id", "status"], name: "index_pending_actions_on_user_id_and_status"
    t.index ["user_id"], name: "index_pending_actions_on_user_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.string "resource", null: false
    t.string "action", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource", "action"], name: "index_permissions_on_resource_and_action", unique: true
  end

  create_table "recurring_obligations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "category_id"
    t.string "name", null: false
    t.integer "amount", default: 0, null: false
    t.integer "due_day"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "allocatable_type"
    t.bigint "allocatable_id"
    t.text "notes"
    t.jsonb "ai_analysis", default: [], null: false
    t.bigint "account_id"
    t.index ["account_id", "active"], name: "index_recurring_obligations_on_account_id_and_active"
    t.index ["account_id"], name: "index_recurring_obligations_on_account_id"
    t.index ["allocatable_type", "allocatable_id"], name: "index_recurring_obligations_on_allocatable"
    t.index ["category_id"], name: "index_recurring_obligations_on_category_id"
    t.index ["user_id", "active"], name: "index_recurring_obligations_on_user_id_and_active"
    t.index ["user_id"], name: "index_recurring_obligations_on_user_id"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_roles_on_slug", unique: true
  end

  create_table "service_accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "token_hash"
    t.boolean "active", default: true, null: false
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_service_accounts_on_slug", unique: true
    t.index ["token_hash"], name: "index_service_accounts_on_token_hash"
  end

  create_table "subcategories", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "name", null: false
    t.string "code", null: false
    t.boolean "is_system", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "code"], name: "index_subcategories_on_category_id_and_code"
    t.index ["category_id"], name: "index_subcategories_on_category_id"
  end

  create_table "telegram_updates", force: :cascade do |t|
    t.bigint "update_id", null: false
    t.string "update_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.boolean "consumed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["consumed"], name: "index_telegram_updates_on_consumed"
    t.index ["update_id"], name: "index_telegram_updates_on_update_id", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "date", null: false
    t.string "concept", null: false
    t.string "product"
    t.integer "amount", null: false
    t.string "transaction_type", default: "expense", null: false
    t.bigint "category_id"
    t.bigint "subcategory_id"
    t.string "source", default: "manual"
    t.string "status", default: "confirmed", null: false
    t.datetime "clarification_requested_at"
    t.datetime "clarification_resolved_at"
    t.jsonb "metadata", default: {}
    t.integer "year", null: false
    t.integer "month", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.string "source_event_id"
    t.index ["account_id", "source", "source_event_id"], name: "idx_on_account_id_source_source_event_id_5beb8b9a55", unique: true, where: "(source_event_id IS NOT NULL)"
    t.index ["account_id", "status"], name: "index_transactions_on_account_id_and_status"
    t.index ["account_id", "year", "month"], name: "index_transactions_on_account_id_and_year_and_month"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["subcategory_id"], name: "index_transactions_on_subcategory_id"
    t.index ["user_id", "status"], name: "index_transactions_on_user_id_and_status"
    t.index ["user_id", "year", "month"], name: "index_transactions_on_user_id_and_year_and_month"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "encrypted_password"
    t.string "name", null: false
    t.string "refresh_token_hash"
    t.datetime "refresh_token_expires_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "super_admin", default: false, null: false
    t.string "google_uid"
    t.string "avatar_url"
    t.string "auth_provider"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true, where: "(google_uid IS NOT NULL)"
    t.index ["refresh_token_hash"], name: "index_users_on_refresh_token_hash"
  end

  add_foreign_key "accounts", "users", column: "owner_user_id"
  add_foreign_key "budgets", "accounts"
  add_foreign_key "budgets", "categories"
  add_foreign_key "budgets", "users"
  add_foreign_key "categories", "accounts"
  add_foreign_key "categories", "users"
  add_foreign_key "debts", "accounts"
  add_foreign_key "debts", "users"
  add_foreign_key "delegations", "accounts"
  add_foreign_key "delegations", "agent_types"
  add_foreign_key "delegations", "service_accounts"
  add_foreign_key "delegations", "users"
  add_foreign_key "financial_contexts", "accounts"
  add_foreign_key "financial_contexts", "users"
  add_foreign_key "income_sources", "accounts"
  add_foreign_key "income_sources", "users"
  add_foreign_key "pending_actions", "accounts"
  add_foreign_key "pending_actions", "users"
  add_foreign_key "recurring_obligations", "accounts"
  add_foreign_key "recurring_obligations", "categories"
  add_foreign_key "recurring_obligations", "users"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "subcategories", "categories"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "subcategories"
  add_foreign_key "transactions", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
end
