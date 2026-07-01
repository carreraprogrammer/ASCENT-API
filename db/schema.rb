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

ActiveRecord::Schema[8.0].define(version: 2026_06_30_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_progress", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "xp", default: 0, null: false
    t.integer "level", default: 0, null: false
    t.integer "streak_days", default: 0, null: false
    t.date "last_activity_date"
    t.decimal "readiness_score", precision: 5, scale: 2, default: "0.0", null: false
    t.string "avatar_seed", default: "", null: false
    t.boolean "bypass_readiness", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_progress_on_account_id", unique: true
  end

  create_table "accounts", force: :cascade do |t|
    t.bigint "owner_user_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "active", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "financial_level", default: 1, null: false
    t.string "telegram_chat_id"
    t.index ["owner_user_id"], name: "index_accounts_on_owner_user_id"
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
  end

  create_table "agent_insights", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "generated_at", null: false
    t.text "agent_reasoning"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "insightable_type"
    t.bigint "insightable_id"
    t.string "insight_kind", default: "tip", null: false
    t.string "title", default: "", null: false
    t.text "body", default: "", null: false
    t.string "status", default: "new", null: false
    t.index ["account_id", "status"], name: "index_agent_insights_on_account_and_status"
    t.index ["account_id"], name: "index_agent_insights_on_account_id"
    t.index ["insightable_type", "insightable_id"], name: "index_agent_insights_on_insightable"
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

  create_table "agent_ui_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "session_id"
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "consumed_at"], name: "index_agent_ui_events_on_account_id_and_consumed_at"
    t.index ["account_id"], name: "index_agent_ui_events_on_account_id"
    t.index ["session_id"], name: "index_agent_ui_events_on_session_id"
  end

  create_table "budget_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "code", null: false
    t.string "name", null: false
    t.string "category_type", null: false
    t.boolean "system", default: false, null: false
    t.boolean "active", default: true, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "code"], name: "index_budget_categories_on_account_id_and_code", unique: true
    t.index ["account_id"], name: "index_budget_categories_on_account_id"
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
    t.integer "subcategory_id"
    t.index ["account_id", "category_id", "month", "year"], name: "index_budgets_on_account_category_month_year_no_subcat", unique: true, where: "(subcategory_id IS NULL)"
    t.index ["account_id", "subcategory_id", "month", "year"], name: "index_budgets_on_account_subcategory_month_year", unique: true, where: "(subcategory_id IS NOT NULL)"
    t.index ["account_id"], name: "index_budgets_on_account_id"
    t.index ["category_id"], name: "index_budgets_on_category_id"
    t.index ["subcategory_id"], name: "index_budgets_on_subcategory_id"
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

  create_table "chat_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "channel", default: "app", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "channel", "created_at"], name: "index_chat_messages_on_account_id_and_channel_and_created_at"
    t.index ["account_id"], name: "index_chat_messages_on_account_id"
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
    t.date "interest_last_applied_on"
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

  create_table "email_connections", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "provider", default: "gmail", null: false
    t.text "access_token_ciphertext", null: false
    t.text "refresh_token_ciphertext", null: false
    t.datetime "expires_at"
    t.datetime "connected_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "bank_senders"
    t.string "gmail_address"
    t.string "gmail_history_id"
    t.datetime "gmail_watch_expires_at"
    t.datetime "reconnect_required_at"
    t.index ["account_id"], name: "index_email_connections_on_account_id", unique: true
    t.index ["gmail_address"], name: "index_email_connections_on_gmail_address", unique: true, where: "(gmail_address IS NOT NULL)"
  end

  create_table "error_reports", force: :cascade do |t|
    t.string "error_hash", null: false
    t.string "exception_class", null: false
    t.text "message", null: false
    t.text "stacktrace", null: false
    t.string "endpoint"
    t.string "http_method"
    t.jsonb "params", default: {}
    t.integer "occurrence_count", default: 1, null: false
    t.string "status", default: "pending", null: false
    t.string "pr_url"
    t.jsonb "pending_fix"
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["error_hash"], name: "index_error_reports_on_error_hash", unique: true
    t.index ["status"], name: "index_error_reports_on_status"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "feature_key", null: false
    t.string "status", default: "locked", null: false
    t.datetime "unlocked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "feature_key"], name: "index_feature_flags_on_account_id_and_feature_key", unique: true
    t.index ["account_id"], name: "index_feature_flags_on_account_id"
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
    t.datetime "debts_confirmed_at"
    t.integer "monthly_goal_contribution"
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

  create_table "income_source_schedules", force: :cascade do |t|
    t.bigint "income_source_id", null: false
    t.integer "ordinal", default: 1, null: false
    t.string "label"
    t.integer "expected_day_from", null: false
    t.integer "expected_day_to", null: false
    t.integer "expected_amount", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["income_source_id", "ordinal"], name: "index_income_source_schedules_on_source_and_ordinal", unique: true
    t.index ["income_source_id"], name: "index_income_source_schedules_on_income_source_id"
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
    t.string "classification"
    t.string "cadence"
    t.integer "reliability_score"
    t.datetime "last_confirmed_at"
    t.string "evidence_source"
    t.text "notes"
    t.index ["account_id", "active"], name: "index_income_sources_on_account_id_and_active"
    t.index ["account_id", "classification"], name: "index_income_sources_on_account_id_and_classification"
    t.index ["account_id"], name: "index_income_sources_on_account_id"
    t.index ["user_id", "active"], name: "index_income_sources_on_user_id_and_active"
    t.index ["user_id"], name: "index_income_sources_on_user_id"
  end

  create_table "monthly_financial_plans", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id"
    t.integer "month", null: false
    t.integer "year", null: false
    t.string "status", default: "draft", null: false
    t.string "mode", default: "conservative", null: false
    t.integer "base_budget_income", default: 0, null: false
    t.integer "expected_variable_income", default: 0, null: false
    t.integer "recurring_obligations_total", default: 0, null: false
    t.integer "debt_minimums_total", default: 0, null: false
    t.integer "protected_buffer_amount", default: 0, null: false
    t.integer "discretionary_limit", default: 0, null: false
    t.string "overflow_rule", default: "debt", null: false
    t.jsonb "overflow_rule_detail", default: {}, null: false
    t.integer "reward_pct"
    t.integer "investment_target"
    t.string "debt_strategy"
    t.jsonb "assumptions", default: {}, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "income_actual", default: 0, null: false
    t.integer "expense_actual", default: 0, null: false
    t.jsonb "execution_snapshot", default: {}, null: false
    t.datetime "closed_at"
    t.index ["account_id", "year", "month"], name: "index_monthly_financial_plans_on_account_and_period", unique: true
    t.index ["account_id"], name: "index_monthly_financial_plans_on_account_id"
    t.index ["user_id"], name: "index_monthly_financial_plans_on_user_id"
  end

  create_table "night_analyses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "analysis_date", null: false
    t.string "health_status", null: false
    t.integer "commitment_gap", null: false
    t.integer "daily_burn", null: false
    t.integer "days_to_next_income"
    t.jsonb "category_alerts", default: [], null: false
    t.jsonb "transactions_context", default: {}, null: false
    t.jsonb "burn_vs_plan", default: [], null: false
    t.text "agent_reasoning"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "analysis_date"], name: "index_night_analyses_on_account_and_date", unique: true
    t.index ["account_id"], name: "index_night_analyses_on_account_id"
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
    t.string "actionable_type"
    t.bigint "actionable_id"
    t.index ["account_id", "status"], name: "index_pending_actions_on_account_id_and_status"
    t.index ["account_id"], name: "index_pending_actions_on_account_id"
    t.index ["actionable_type", "actionable_id"], name: "index_pending_actions_on_actionable"
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

  create_table "planned_expenses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id"
    t.bigint "category_id", null: false
    t.bigint "subcategory_id", null: false
    t.string "name", null: false
    t.integer "amount_estimated", default: 0, null: false
    t.date "target_date", null: false
    t.string "planning_type", null: false
    t.string "status", default: "planned", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "planning_type"], name: "index_planned_expenses_on_account_id_and_planning_type"
    t.index ["account_id", "status"], name: "index_planned_expenses_on_account_id_and_status"
    t.index ["account_id", "target_date"], name: "index_planned_expenses_on_account_id_and_target_date"
    t.index ["account_id"], name: "index_planned_expenses_on_account_id"
    t.index ["category_id"], name: "index_planned_expenses_on_category_id"
    t.index ["subcategory_id"], name: "index_planned_expenses_on_subcategory_id"
    t.index ["user_id"], name: "index_planned_expenses_on_user_id"
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
    t.text "notes"
    t.jsonb "ai_analysis", default: [], null: false
    t.bigint "account_id"
    t.string "budget_category"
    t.bigint "subcategory_id"
    t.string "source_type"
    t.bigint "source_id"
    t.date "end_date"
    t.index ["account_id", "active"], name: "index_recurring_obligations_on_account_id_and_active"
    t.index ["account_id", "budget_category"], name: "index_recurring_obligations_on_account_budget_category"
    t.index ["account_id"], name: "index_recurring_obligations_on_account_id"
    t.index ["category_id"], name: "index_recurring_obligations_on_category_id"
    t.index ["end_date"], name: "index_recurring_obligations_on_end_date"
    t.index ["source_type", "source_id"], name: "index_recurring_obligations_on_source"
    t.index ["subcategory_id"], name: "index_recurring_obligations_on_subcategory_id"
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

  create_table "savings_goals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id"
    t.string "name", null: false
    t.integer "target_amount", null: false
    t.integer "current_amount", default: 0, null: false
    t.date "target_date"
    t.integer "monthly_contribution", default: 0
    t.integer "monthly_contribution_needed"
    t.string "status", default: "active"
    t.integer "priority", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_savings_goals_on_account_id"
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

  create_table "sinking_funds", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id"
    t.string "name", null: false
    t.integer "monthly_contribution", default: 0, null: false
    t.integer "target_amount"
    t.date "target_date"
    t.integer "current_balance", default: 0, null: false
    t.string "budget_category"
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "planned_expense_id"
    t.boolean "auto_debit", default: false, null: false
    t.date "last_auto_debit_on"
    t.integer "debit_day", default: 1, null: false
    t.index ["account_id", "active"], name: "index_sinking_funds_on_account_id_and_active"
    t.index ["account_id"], name: "index_sinking_funds_on_account_id"
    t.index ["planned_expense_id"], name: "index_sinking_funds_on_planned_expense_id"
    t.index ["planned_expense_id"], name: "index_sinking_funds_on_planned_expense_id_unique", unique: true, where: "(planned_expense_id IS NOT NULL)"
    t.index ["user_id"], name: "index_sinking_funds_on_user_id"
  end

  create_table "subcategories", force: :cascade do |t|
    t.bigint "category_id"
    t.string "name", null: false
    t.string "code", null: false
    t.boolean "is_system", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "icon", limit: 50
    t.integer "user_id"
    t.index ["category_id", "code"], name: "index_subcategories_on_category_id_and_code"
    t.index ["category_id"], name: "index_subcategories_on_category_id"
    t.index ["user_id"], name: "index_subcategories_on_user_id"
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
    t.string "payment_source"
    t.string "credit_card_status"
    t.bigint "debt_id"
    t.bigint "recurring_obligation_id"
    t.bigint "income_source_id"
    t.bigint "sinking_fund_id"
    t.integer "covers_period_month"
    t.integer "covers_period_year"
    t.bigint "savings_goal_id"
    t.index ["account_id", "covers_period_year", "covers_period_month"], name: "index_transactions_on_account_covers_period", where: "(covers_period_month IS NOT NULL)"
    t.index ["account_id", "debt_id", "year", "month"], name: "index_transactions_on_account_debt_period"
    t.index ["account_id", "income_source_id", "year", "month"], name: "index_transactions_on_account_income_source_period"
    t.index ["account_id", "payment_source", "credit_card_status"], name: "index_transactions_on_account_credit_card_pending", where: "(((payment_source)::text = 'credit_card'::text) AND ((credit_card_status)::text = 'pending'::text))"
    t.index ["account_id", "savings_goal_id", "year", "month"], name: "index_transactions_on_account_savings_goal_period"
    t.index ["account_id", "sinking_fund_id", "year", "month"], name: "index_transactions_on_account_sinking_fund_period"
    t.index ["account_id", "source", "source_event_id"], name: "idx_on_account_id_source_source_event_id_5beb8b9a55", unique: true, where: "(source_event_id IS NOT NULL)"
    t.index ["account_id", "status"], name: "index_transactions_on_account_id_and_status"
    t.index ["account_id", "year", "month"], name: "index_transactions_on_account_id_and_year_and_month"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["debt_id"], name: "index_transactions_on_debt_id"
    t.index ["income_source_id"], name: "index_transactions_on_income_source_id"
    t.index ["recurring_obligation_id"], name: "index_transactions_on_recurring_obligation_id"
    t.index ["savings_goal_id"], name: "index_transactions_on_savings_goal_id"
    t.index ["sinking_fund_id"], name: "index_transactions_on_sinking_fund_id"
    t.index ["subcategory_id"], name: "index_transactions_on_subcategory_id"
    t.index ["user_id", "status"], name: "index_transactions_on_user_id_and_status"
    t.index ["user_id", "year", "month"], name: "index_transactions_on_user_id_and_year_and_month"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "user_milestones", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id"
    t.string "code", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "achieved_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "code"], name: "index_user_milestones_on_account_and_code", unique: true
    t.index ["account_id"], name: "index_user_milestones_on_account_id"
    t.index ["user_id"], name: "index_user_milestones_on_user_id"
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
    t.string "city"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true, where: "(google_uid IS NOT NULL)"
    t.index ["refresh_token_hash"], name: "index_users_on_refresh_token_hash"
  end

  create_table "xp_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "action_type", null: false
    t.integer "xp_amount", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_xp_events_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_xp_events_on_account_id"
  end

  add_foreign_key "account_progress", "accounts"
  add_foreign_key "accounts", "users", column: "owner_user_id"
  add_foreign_key "agent_insights", "accounts"
  add_foreign_key "agent_ui_events", "accounts"
  add_foreign_key "budget_categories", "accounts"
  add_foreign_key "budgets", "accounts"
  add_foreign_key "budgets", "categories"
  add_foreign_key "budgets", "subcategories"
  add_foreign_key "budgets", "users"
  add_foreign_key "categories", "accounts"
  add_foreign_key "categories", "users"
  add_foreign_key "chat_messages", "accounts"
  add_foreign_key "debts", "accounts"
  add_foreign_key "debts", "users"
  add_foreign_key "delegations", "accounts"
  add_foreign_key "delegations", "agent_types"
  add_foreign_key "delegations", "service_accounts"
  add_foreign_key "delegations", "users"
  add_foreign_key "email_connections", "accounts"
  add_foreign_key "feature_flags", "accounts"
  add_foreign_key "financial_contexts", "accounts"
  add_foreign_key "financial_contexts", "users"
  add_foreign_key "income_source_schedules", "income_sources"
  add_foreign_key "income_sources", "accounts"
  add_foreign_key "income_sources", "users"
  add_foreign_key "monthly_financial_plans", "accounts"
  add_foreign_key "monthly_financial_plans", "users"
  add_foreign_key "night_analyses", "accounts"
  add_foreign_key "pending_actions", "accounts"
  add_foreign_key "pending_actions", "users"
  add_foreign_key "planned_expenses", "accounts"
  add_foreign_key "planned_expenses", "categories"
  add_foreign_key "planned_expenses", "subcategories"
  add_foreign_key "planned_expenses", "users"
  add_foreign_key "recurring_obligations", "accounts"
  add_foreign_key "recurring_obligations", "categories"
  add_foreign_key "recurring_obligations", "subcategories"
  add_foreign_key "recurring_obligations", "users"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "sinking_funds", "accounts"
  add_foreign_key "sinking_funds", "planned_expenses"
  add_foreign_key "sinking_funds", "users"
  add_foreign_key "subcategories", "categories"
  add_foreign_key "subcategories", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "debts"
  add_foreign_key "transactions", "income_sources"
  add_foreign_key "transactions", "recurring_obligations"
  add_foreign_key "transactions", "savings_goals"
  add_foreign_key "transactions", "sinking_funds"
  add_foreign_key "transactions", "subcategories"
  add_foreign_key "transactions", "users"
  add_foreign_key "user_milestones", "accounts"
  add_foreign_key "user_milestones", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "xp_events", "accounts"
end
