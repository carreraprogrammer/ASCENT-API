class AddExecutionFieldsToMonthlyFinancialPlans < ActiveRecord::Migration[8.0]
  def change
    change_table :monthly_financial_plans, bulk: true do |t|
      t.integer :income_actual, default: 0, null: false
      t.integer :expense_actual, default: 0, null: false
      t.jsonb :execution_snapshot, default: {}, null: false
      t.datetime :closed_at
    end
  end
end
