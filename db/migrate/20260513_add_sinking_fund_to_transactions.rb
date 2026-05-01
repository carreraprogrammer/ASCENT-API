class AddSinkingFundToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_reference :transactions, :sinking_fund, foreign_key: true, null: true
    add_index :transactions, [ :account_id, :sinking_fund_id, :year, :month ],
              name: "index_transactions_on_account_sinking_fund_period"
  end
end
