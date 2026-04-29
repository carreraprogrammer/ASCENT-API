class AddDebtLinksToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_reference :transactions, :debt, foreign_key: true, null: true
    add_reference :transactions, :recurring_obligation, foreign_key: true, null: true
    add_index :transactions, [ :account_id, :debt_id, :year, :month ],
              name: "index_transactions_on_account_debt_period"
  end
end
