class AddSavingsGoalToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_reference :transactions, :savings_goal, foreign_key: true, null: true
    add_index :transactions, [ :account_id, :savings_goal_id, :year, :month ],
              name: "index_transactions_on_account_savings_goal_period"
  end
end
