class AddPlannedExpenseToSinkingFunds < ActiveRecord::Migration[8.0]
  def change
    add_reference :sinking_funds, :planned_expense, null: true, foreign_key: true
    add_index :sinking_funds, :planned_expense_id, unique: true,
              where: "planned_expense_id IS NOT NULL",
              name: "index_sinking_funds_on_planned_expense_id_unique"
  end
end
