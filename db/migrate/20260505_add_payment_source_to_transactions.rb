class AddPaymentSourceToTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :transactions, :payment_source, :string
    add_column :transactions, :credit_card_status, :string

    add_index :transactions, [:account_id, :payment_source, :credit_card_status],
              name: "index_transactions_on_account_credit_card_pending",
              where: "payment_source = 'credit_card' AND credit_card_status = 'pending'"
  end
end
