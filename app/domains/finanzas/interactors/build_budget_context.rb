module Finanzas
  module Interactors
    class BuildBudgetContext
      VARIABLE_CLASSIFICATIONS = %w[variable seasonal one_time].freeze

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
                           .reject { |o| o[:allocatable_type] == "Debt" }
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

        {
          income: {
            fixed_total:         fixed_total,
            variable_projection: variable_proj,
            variable_sources:    variable_sources.map { |s| variable_source_summary(s) },
            fixed_sources:       fixed_sources.map { |s| { name: s[:name], amount: s[:expected_amount] } }
          },
          obligations: {
            total:       obligations_total,
            by_category: build_by_category(obligations_by_category)
          },
          debt_minimums: {
            total: debt_minimums_total,
            debts: debts.map { |d| { id: d[:id], name: d[:name], monthly_payment: d[:monthly_payment], current_balance: d[:current_balance] } }
          },
          financial_context: {
            phase:      ctx[:phase],
            strategy:   ctx[:strategy],
            reward_pct: ctx[:reward_pct]
          },
          existing_plan: existing_plan,
          gaps: {
            missing_income:       income_sources.empty?,
            missing_obligations:  obligations.empty?,
            obligations_seem_low: obligations_total < (fixed_total * 0.15).round && fixed_total > 0
          }
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
    end
  end
end
