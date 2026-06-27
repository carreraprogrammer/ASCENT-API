class AddDebitDayToSinkingFunds < ActiveRecord::Migration[8.0]
  def change
    add_column :sinking_funds, :debit_day, :integer, null: false, default: 1
  end
end
