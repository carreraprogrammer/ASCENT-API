module Finanzas
  module Interactors
    class CloseMonthlyPlan
      def initialize(plan_repo: Finanzas::Repositories::MonthlyFinancialPlanRepository.new)
        @plan_repo = plan_repo
      end

      def call(account_id:, plan_id:)
        plan = ::MonthlyFinancialPlan.find_by(id: plan_id, account_id: account_id)
        raise Finanzas::Errors::PlanNotFound, "Monthly financial plan not found" unless plan
        raise Finanzas::Errors::PlanNotConfirmed, "Monthly financial plan must be confirmed before closing" if plan.confirmed_at.nil?

        income_actual = confirmed_transactions(plan, "income").sum(:amount).to_i
        expense_actual = confirmed_transactions(plan, "expense").sum(:amount).to_i
        actuals_by_category = confirmed_transactions(plan, "expense")
          .where.not(category_id: nil)
          .group(:category_id)
          .sum(:amount)

        categories = build_categories(plan, actuals_by_category)
        overflow_amount = [
          income_actual -
            expense_actual -
            plan.recurring_obligations_total.to_i -
            plan.debt_minimums_total.to_i -
            plan.protected_buffer_amount.to_i,
          0
        ].max

        snapshot = {
          income_actual: income_actual,
          expense_actual: expense_actual,
          categories: categories,
          overflow_applied: plan.overflow_rule,
          overflow_amount: overflow_amount,
          closed_at: Time.current.iso8601
        }

        result = @plan_repo.close(
          plan.id,
          snapshot: snapshot,
          income_actual: income_actual,
          expense_actual: expense_actual,
          account_id: account_id
        )

        EventBus.publish("xp.month_closed_with_snapshot", account_id: account_id, plan_id: plan.id)
        result
      end

      private

      def confirmed_transactions(plan, transaction_type)
        ::Transaction.where(
          account_id: plan.account_id,
          month: plan.month,
          year: plan.year,
          status: "confirmed",
          transaction_type: transaction_type
        )
      end

      def build_categories(plan, actuals_by_category)
        budgets_by_category = ::Budget
          .where(account_id: plan.account_id, month: plan.month, year: plan.year)
          .includes(:category)
          .group_by(&:category_id)

        budgets_by_category.map do |category_id, budgets|
          category = budgets.first.category
          budgeted = budgets.sum { |budget| budget.amount_limit.to_i }
          actual = actuals_by_category[category_id].to_i
          variance = actual - budgeted

          {
            code: category&.code,
            name: category&.name,
            budgeted: budgeted,
            actual: actual,
            variance: variance,
            variance_pct: budgeted.positive? ? ((variance.to_f / budgeted) * 100).round : nil
          }
        end
      end
    end
  end
end
