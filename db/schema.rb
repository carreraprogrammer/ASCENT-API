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

ActiveRecord::Schema[8.0].define(version: 17) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "budgets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "category_id", null: false
    t.integer "month", null: false
    t.integer "year", null: false
    t.integer "amount_limit", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["user_id", "status"], name: "index_debts_on_user_id_and_status"
    t.index ["user_id"], name: "index_debts_on_user_id"
  end

  create_table "financial_contexts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "phase", default: "debt_payoff", null: false
    t.string "strategy", default: "snowball", null: false
    t.integer "monthly_income_1", default: 0, null: false
    t.integer "monthly_income_2", default: 0, null: false
    t.integer "income_day_1", default: 4, null: false
    t.integer "income_day_2", default: 19, null: false
    t.integer "monthly_rent", default: 0, null: false
    t.integer "reward_pct", default: 5, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  add_foreign_key "budgets", "categories"
  add_foreign_key "budgets", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "debts", "users"
  add_foreign_key "financial_contexts", "users"
  add_foreign_key "pending_actions", "users"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "subcategories", "categories"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "subcategories"
  add_foreign_key "transactions", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
end
