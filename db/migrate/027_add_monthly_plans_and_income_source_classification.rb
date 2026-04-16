class AddMonthlyPlansAndIncomeSourceClassification < ActiveRecord::Migration[8.0]
  def change
    change_table :income_sources, bulk: true do |t|
      t.string   :classification
      t.string   :cadence
      t.integer  :reliability_score
      t.datetime :last_confirmed_at
      t.string   :evidence_source
    end

    add_index :income_sources, [ :account_id, :classification ], name: "index_income_sources_on_account_id_and_classification"

    create_table :monthly_financial_plans do |t|
      t.references :user,    null: false, foreign_key: true
      t.references :account, null: true,  foreign_key: true
      t.integer :month,                    null: false
      t.integer :year,                     null: false
      t.string  :status, default: "draft", null: false
      t.string  :mode,   default: "conservative", null: false
      t.integer :base_budget_income,       null: false, default: 0
      t.integer :expected_variable_income, null: false, default: 0
      t.integer :recurring_obligations_total, null: false, default: 0
      t.integer :debt_minimums_total,      null: false, default: 0
      t.integer :protected_buffer_amount,  null: false, default: 0
      t.integer :discretionary_limit,      null: false, default: 0
      t.string  :overflow_rule,            null: false, default: "debt"
      t.jsonb   :overflow_rule_detail,     null: false, default: {}
      t.integer :reward_pct
      t.integer :investment_target
      t.string  :debt_strategy
      t.jsonb   :assumptions,              null: false, default: {}
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :monthly_financial_plans, [ :account_id, :year, :month ], unique: true, name: "index_monthly_financial_plans_on_account_and_period"
  end
end
