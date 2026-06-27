class AddAutoDebitToSinkingFunds < ActiveRecord::Migration[8.0]
  def change
    add_column :sinking_funds, :auto_debit, :boolean, null: false, default: false
    add_column :sinking_funds, :last_auto_debit_on, :date
  end
end
