module Finanzas
  module Interactors
    class GenerateMonthlyFinancialPlan
      VARIABLE_CLASSIFICATIONS = %w[variable seasonal one_time].freeze

      def initialize(
        plan_repo: Finanzas::Repositories::MonthlyFinancialPlanRepository.new,
        income_repo: Finanzas::Repositories::IncomeSourceRepository.new,
        recurring_repo: Finanzas::Repositories::RecurringObligationRepository.new,
        debt_repo: Finanzas::Repositories::DebtRepository.new,
        ctx_repo: Finanzas::Repositories::FinancialContextRepository.new
      )
        @plan_repo = plan_repo
        @income_repo = income_repo
        @recurring_repo = recurring_repo
        @debt_repo = debt_repo
        @ctx_repo = ctx_repo
      end

      def call(user_id:, account_id:, month:, year:, mode: "conservative")
        raise Finanzas::Errors::InvalidTransaction, "mode invalido" unless MonthlyFinancialPlan::MODES.include?(mode.to_s)

        income_sources = @income_repo.active_for_account(account_id)
        base_sources, variable_sources = income_sources.partition { |source| base_source?(source) }

        base_income = base_sources.sum { |source| source[:expected_amount].to_i }
        variable_income = variable_sources.sum { |source| source[:expected_amount].to_i }
        weighted_variable_income = variable_sources.sum do |source|
          score = source[:reliability_score] || 50
          (source[:expected_amount].to_i * (score / 100.0)).round
        end
        planning_income = mode.to_s == "expected" ? base_income + weighted_variable_income : base_income

        recurring_total = @recurring_repo.active_for_account(account_id)
                                         .reject { |item| debt_linked_obligation?(item) }
                                         .sum { |item| item[:amount].to_i }
        debt_minimums_total = @debt_repo.active_for_account(account_id).sum { |debt| debt[:monthly_payment].to_i }

        protected_buffer_amount = round_to_thousands((planning_income * 0.05).round)
        available_after_fixed = [ planning_income - recurring_total - debt_minimums_total - protected_buffer_amount, 0 ].max
        discretionary_limit = [ round_to_thousands((planning_income * 0.10).round), available_after_fixed ].min

        ctx = @ctx_repo.find_by_account(account_id) || {}
        overflow_rule = infer_overflow_rule(ctx[:phase])

        @plan_repo.upsert(
          user_id: user_id,
          account_id: account_id,
          month: month,
          year: year,
          attrs: {
            status: "draft",
            mode: mode.to_s,
            base_budget_income: base_income,
            expected_variable_income: variable_income,
            recurring_obligations_total: recurring_total,
            debt_minimums_total: debt_minimums_total,
            protected_buffer_amount: protected_buffer_amount,
            discretionary_limit: discretionary_limit,
            overflow_rule: overflow_rule,
            reward_pct: ctx[:reward_pct] || 5,
            debt_strategy: ctx[:strategy],
            assumptions: {
              planning_income_used: planning_income,
              base_sources: base_sources.map { |source| source[:name] },
              variable_sources: variable_sources.map { |source|
                { name: source[:name], reliability_score: source[:reliability_score] || 50 }
              },
              weighted_variable_income: weighted_variable_income,
              generated_from: "income_sources",
              generated_at: Time.current.iso8601
            }
          }
        )
      end

      private

      def base_source?(source)
        classification = source[:classification].presence
        return !VARIABLE_CLASSIFICATIONS.include?(classification) if classification.present?

        !source[:is_variable]
      end

      def infer_overflow_rule(phase)
        case phase
        when "debt_payoff" then "debt"
        when "emergency_fund" then "emergency_fund"
        when "investing", "wealth_building" then "investment"
        else "mixed"
        end
      end

      def round_to_thousands(amount)
        ((amount.to_f / 1000).round * 1000).to_i
      end

      def debt_linked_obligation?(obligation)
        obligation[:source_type] == "Debt" || obligation[:allocatable_type] == "Debt"
      end
    end
  end
end
