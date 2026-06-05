module Finanzas
  module Interactors
    class BuildBudgetContext
      VARIABLE_CLASSIFICATIONS = %w[variable seasonal one_time].freeze
      SPENDING_HISTORY_MONTHS = 3

      def initialize(
        income_repo:   Finanzas::Repositories::IncomeSourceRepository.new,
        recurring_repo: Finanzas::Repositories::RecurringObligationRepository.new,
        debt_repo:     Finanzas::Repositories::DebtRepository.new,
        ctx_repo:      Finanzas::Repositories::FinancialContextRepository.new,
        plan_repo:     Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      )
        @income_repo   = income_repo
        @recurring_repo = recurring_repo
        @debt_repo     = debt_repo
        @ctx_repo      = ctx_repo
        @plan_repo     = plan_repo
      end

      def call(account_id:, month:, year:)
        income_sources = @income_repo.active_for_account(account_id)
        obligations    = @recurring_repo.active_for_account(account_id)
                           .reject { |o| debt_linked_obligation?(o) }
        debts          = @debt_repo.active_for_account(account_id)
        ctx            = @ctx_repo.find_by_account(account_id) || {}
        existing_plan  = @plan_repo.find_for_month(account_id: account_id, month: month, year: year)

        fixed_sources, variable_sources = income_sources.partition { |s| base_source?(s) }
        fixed_total    = fixed_sources.sum { |s| s[:expected_amount].to_i }
        variable_proj  = variable_sources.sum do |s|
          score = (s[:reliability_score] || 50) / 100.0
          (s[:expected_amount].to_i * score).round
        end

        obligations_by_category = obligations.group_by { |o| o[:budget_category] || "uncategorized" }
        obligations_total = obligations.sum { |o| o[:amount].to_i }
        debt_minimums_total = debts.sum { |d| d[:monthly_payment].to_i }

        expiring_soon    = obligations.select { |o| o[:end_date].present? && o[:end_date] <= Date.current + 2.months }
        temporary_total  = obligations.select { |o| o[:temporary] }.sum { |o| o[:amount].to_i }
        goal_contribution = ctx[:monthly_goal_contribution].to_i

        {
          income: {
            fixed_total:         fixed_total,
            variable_projection: variable_proj,
            variable_sources:    variable_sources.map { |s| variable_source_summary(s) },
            fixed_sources:       fixed_sources.map { |s| { name: s[:name], amount: s[:expected_amount] } }
          },
          obligations: {
            total:           obligations_total,
            temporary_total: temporary_total,
            by_category:     build_by_category(obligations_by_category)
          },
          debt_minimums: {
            total: debt_minimums_total,
            debts: debts.map { |d| { id: d[:id], name: d[:name], monthly_payment: d[:monthly_payment], current_balance: d[:current_balance] } }
          },
          goal_contribution: {
            amount: goal_contribution,
            phase:  ctx[:phase],
            label:  goal_contribution_label(ctx[:phase])
          },
          financial_context: {
            phase:                     ctx[:phase],
            strategy:                  ctx[:strategy],
            reward_pct:                ctx[:reward_pct],
            monthly_goal_contribution: goal_contribution
          },
          existing_plan:    existing_plan,
          expiring_soon:    expiring_soon.map { |o| { id: o[:id], name: o[:name], amount: o[:amount], end_date: o[:end_date] } },
          gaps: {
            missing_income:       income_sources.empty?,
            missing_obligations:  obligations.empty?,
            obligations_seem_low: obligations_total < (fixed_total * 0.15).round && fixed_total > 0
          },
          spending_history:   build_spending_history(account_id),
          planned_expenses:   build_planned_expenses(account_id),
          sinking_funds:      build_sinking_funds(account_id),
          budget_categories:  build_budget_categories(account_id)
        }
      end

      private

      def base_source?(source)
        classification = source[:classification].presence
        return !VARIABLE_CLASSIFICATIONS.include?(classification) if classification.present?

        !source[:is_variable]
      end

      def variable_source_summary(source)
        score = source[:reliability_score] || 50
        {
          name:              source[:name],
          expected_amount:   source[:expected_amount],
          reliability_score: score,
          conservative_projection: (source[:expected_amount].to_i * (score / 100.0)).round
        }
      end

      def build_by_category(grouped)
        grouped.transform_values do |items|
          {
            total: items.sum { |o| o[:amount].to_i },
            items: items.map { |o| { id: o[:id], name: o[:name], amount: o[:amount], due_day: o[:due_day] } }
          }
        end
      end

      def build_spending_history(account_id)
        since = SPENDING_HISTORY_MONTHS.months.ago.to_date

        rows = ::Transaction
          .joins("LEFT JOIN categories ON categories.id = transactions.category_id")
          .where(account_id: account_id, transaction_type: "expense")
          .where("transactions.date >= ?", since)
          .select(
            "categories.code AS category_code",
            "categories.category_type AS category_type",
            "transactions.year",
            "transactions.month",
            "SUM(transactions.amount) AS total"
          )
          .group("categories.code", "categories.category_type", "transactions.year", "transactions.month")

        # Group by category_code (or fall back to category_type), then average over months
        by_category = Hash.new { |h, k| h[k] = [] }
        rows.each do |row|
          key = row.category_code.presence || row.category_type.presence || "uncategorized"
          by_category[key] << row.total.to_i
        end

        by_category.transform_values do |monthly_totals|
          {
            average_monthly: (monthly_totals.sum.to_f / SPENDING_HISTORY_MONTHS).round,
            months_with_data: monthly_totals.size,
            monthly_totals: monthly_totals
          }
        end
      end

      def build_sinking_funds(account_id)
        ::SinkingFund.where(account_id: account_id).active.map do |sf|
          {
            id:                   sf.id,
            name:                 sf.name,
            monthly_contribution: sf.monthly_contribution,
            current_balance:      sf.current_balance,
            target_amount:        sf.target_amount,
            target_date:          sf.target_date,
            budget_category:      sf.budget_category
          }
        end
      end

      def build_planned_expenses(account_id)
        Finanzas::Repositories::PlannedExpenseRepository.new.planned_for_account(account_id)
      end

      def build_budget_categories(account_id)
        ::BudgetCategory.where(account_id: account_id).active.map do |bc|
          {
            id:            bc.id,
            code:          bc.code,
            name:          bc.name,
            category_type: bc.category_type,
            system:        bc.system,
            sort_order:    bc.sort_order
          }
        end
      end

      def goal_contribution_label(phase)
        case phase.to_s
        when "debt_payoff"     then "Aporte mensual a deuda (objetivo)"
        when "emergency_fund"  then "Aporte mensual a fondo de emergencia"
        when "investing"       then "Aporte mensual a inversión"
        else                        "Aporte a objetivo financiero"
        end
      end

      def debt_linked_obligation?(obligation)
        obligation[:source_type] == "Debt"
      end
    end
  end
end
