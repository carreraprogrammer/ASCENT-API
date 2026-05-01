class BackfillSinkingFundsForPlannedExpenses < ActiveRecord::Migration[8.0]
  class PlannedExpense < ActiveRecord::Base
    self.table_name = "planned_expenses"

    belongs_to :category, class_name: "BackfillSinkingFundsForPlannedExpenses::Category", optional: true
    has_one :sinking_fund, class_name: "BackfillSinkingFundsForPlannedExpenses::SinkingFund"
  end

  class Category < ActiveRecord::Base
    self.table_name = "categories"
  end

  class SinkingFund < ActiveRecord::Base
    self.table_name = "sinking_funds"
  end

  def up
    PlannedExpense.includes(:category, :sinking_fund)
      .where(status: "planned")
      .find_each do |expense|
        next if expense.sinking_fund.present?

        SinkingFund.create!(
          user_id: expense.user_id,
          account_id: expense.account_id,
          planned_expense_id: expense.id,
          name: expense.name,
          monthly_contribution: monthly_contribution_for(expense),
          target_amount: expense.amount_estimated,
          target_date: expense.target_date,
          current_balance: 0,
          budget_category: expense.category&.code,
          active: true,
          notes: "Creado automaticamente desde gasto planeado existente.",
          created_at: Time.current,
          updated_at: Time.current
        )
      end
  end

  def down
    SinkingFund
      .where("notes = ?", "Creado automaticamente desde gasto planeado existente.")
      .delete_all
  end

  private

  def monthly_contribution_for(expense)
    months = months_until(expense.target_date)
    (expense.amount_estimated.to_f / months).ceil
  end

  def months_until(target_date)
    target = target_date || Date.current
    today = Date.current
    delta = (target.year * 12 + target.month) - (today.year * 12 + today.month) + 1
    [ delta, 1 ].max
  end
end
