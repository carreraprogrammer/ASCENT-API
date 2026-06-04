class AddCoversPeriodToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :covers_period_month, :integer
    add_column :transactions, :covers_period_year,  :integer

    add_index :transactions, [ :account_id, :covers_period_year, :covers_period_month ],
              name: "index_transactions_on_account_covers_period",
              where: "covers_period_month IS NOT NULL"
  end
end
