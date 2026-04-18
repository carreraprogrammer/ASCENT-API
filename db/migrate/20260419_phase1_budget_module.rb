class Phase1BudgetModule < ActiveRecord::Migration[8.0]
  BUDGET_CATEGORIES = %w[
    housing utilities groceries transportation health
    debt_payoff dining_leisure personal_care savings_buffer
  ].freeze

  def change
    # 1. budget_category en recurring_obligations
    add_column :recurring_obligations, :budget_category, :string
    add_index  :recurring_obligations, [ :account_id, :budget_category ],
               name: "index_recurring_obligations_on_account_budget_category"

    # 2. Relación polimórfica en pending_actions → apunta al recurso que crea
    add_column :pending_actions, :actionable_type, :string
    add_column :pending_actions, :actionable_id,   :bigint
    add_index  :pending_actions, [ :actionable_type, :actionable_id ],
               name: "index_pending_actions_on_actionable"
  end
end
