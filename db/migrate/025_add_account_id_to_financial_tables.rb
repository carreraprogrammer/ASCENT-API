class AddAccountIdToFinancialTables < ActiveRecord::Migration[8.0]
  TABLES = %i[
    categories
    transactions
    debts
    budgets
    income_sources
    recurring_obligations
    pending_actions
    financial_contexts
  ].freeze

  def change
    TABLES.each do |table_name|
      add_reference table_name, :account, null: true, foreign_key: true
    end

    add_index :transactions, [ :account_id, :year, :month ], name: "index_transactions_on_account_id_and_year_and_month"
    add_index :transactions, [ :account_id, :status ], name: "index_transactions_on_account_id_and_status"
    add_index :debts, [ :account_id, :status ], name: "index_debts_on_account_id_and_status"
    add_index :income_sources, [ :account_id, :active ], name: "index_income_sources_on_account_id_and_active"
    add_index :recurring_obligations, [ :account_id, :active ], name: "index_recurring_obligations_on_account_id_and_active"
    add_index :pending_actions, [ :account_id, :status ], name: "index_pending_actions_on_account_id_and_status"
    add_index :categories, [ :account_id, :code ], name: "index_categories_on_account_id_and_code"
  end
end
