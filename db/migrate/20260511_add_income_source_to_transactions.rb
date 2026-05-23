class AddIncomeSourceToTransactions < ActiveRecord::Migration[7.1]
  def change
    add_reference :transactions, :income_source, foreign_key: true
    add_index :transactions, [ :account_id, :income_source_id, :year, :month ],
              name: "index_transactions_on_account_income_source_period"
  end
end
