class AddMonthlyGoalContributionToFinancialContexts < ActiveRecord::Migration[8.0]
  def change
    add_column :financial_contexts, :monthly_goal_contribution, :integer, null: true
  end
end
