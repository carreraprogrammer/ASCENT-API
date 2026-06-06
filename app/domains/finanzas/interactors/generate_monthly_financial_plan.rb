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

        existing_plan = @plan_repo.find_for_month(account_id: account_id, month: month, year: year)
        previous_plan = @plan_repo.find_last_confirmed(account_id: account_id)
        rolling = previous_plan.present? && existing_plan.nil?

        income_sources = @income_repo.active_for_account(account_id)
        base_sources, variable_sources = income_sources.partition { |source| base_source?(source) }

        calculated_base_income = base_sources.sum { |source| source[:expected_amount].to_i }
        calculated_variable_income = variable_sources.sum { |source| source[:expected_amount].to_i }
        weighted_variable_income = variable_sources.sum do |source|
          score = source[:reliability_score] || 50
          (source[:expected_amount].to_i * (score / 100.0)).round
        end
        calculated_planning_income = mode.to_s == "expected" ? calculated_base_income + weighted_variable_income : calculated_base_income

        calculated_recurring_total = @recurring_repo.active_for_account(account_id)
                                                    .reject { |item| debt_linked_obligation?(item) }
                                                    .sum { |item| item[:amount].to_i }
        calculated_debt_minimums_total = @debt_repo.active_for_account(account_id).sum { |debt| debt[:monthly_payment].to_i }

        calculated_protected_buffer_amount = round_to_thousands((calculated_planning_income * 0.05).round)
        calculated_available_after_fixed = [
          calculated_planning_income -
            calculated_recurring_total -
            calculated_debt_minimums_total -
            calculated_protected_buffer_amount,
          0
        ].max

        ctx   = @ctx_repo.find_by_account(account_id) || {}
        phase = Finanzas::Interactors::DerivePhase.new.call(account_id: account_id)

        disc_rate = discretionary_rate_for_phase(phase)
        calculated_discretionary_limit = [
          round_to_thousands((calculated_planning_income * disc_rate).round),
          calculated_available_after_fixed
        ].min

        calculated_overflow_rule = infer_overflow_rule(phase)
        calculated_reward_pct = ctx[:reward_pct] || 5
        calculated_debt_strategy = ctx[:strategy]

        rolling_changes = []
        base_income = select_rolling_value(
          previous_plan,
          :base_budget_income,
          calculated_base_income,
          rolling_changes,
          rolling: rolling
        )
        variable_income = select_rolling_value(
          previous_plan,
          :expected_variable_income,
          calculated_variable_income,
          rolling_changes,
          rolling: rolling
        )
        recurring_total = select_rolling_value(
          previous_plan,
          :recurring_obligations_total,
          calculated_recurring_total,
          rolling_changes,
          rolling: rolling
        )
        debt_minimums_total = select_rolling_value(
          previous_plan,
          :debt_minimums_total,
          calculated_debt_minimums_total,
          rolling_changes,
          rolling: rolling
        )
        discretionary_limit = select_rolling_value(
          previous_plan,
          :discretionary_limit,
          calculated_discretionary_limit,
          rolling_changes,
          rolling: rolling
        )
        planning_income = mode.to_s == "expected" ? base_income + weighted_variable_income : base_income
        protected_buffer_amount = round_to_thousands((planning_income * 0.05).round)
        overflow_rule = rolling ? previous_plan[:overflow_rule] : calculated_overflow_rule
        reward_pct = rolling ? previous_plan[:reward_pct] || calculated_reward_pct : calculated_reward_pct
        debt_strategy = rolling ? previous_plan[:debt_strategy] : calculated_debt_strategy

        previous_closed        = @plan_repo.last_closed(account_id: account_id, limit: 1).first
        carryover_from_previous = previous_closed&.dig(:execution_snapshot, "overflow_amount").to_i

        assumptions = {
          planning_income_used: planning_income,
          base_sources: base_sources.map { |source| source[:name] },
          variable_sources: variable_sources.map { |source|
            { name: source[:name], reliability_score: source[:reliability_score] || 50 }
          },
          weighted_variable_income: weighted_variable_income,
          discretionary_rate_pct: (disc_rate * 100).round(1),
          financial_phase: phase,
          carryover_from_previous: carryover_from_previous,
          generated_from: "income_sources",
          generated_at: Time.current.iso8601
        }
        if rolling
          assumptions[:inherited_from] = { month: previous_plan[:month], year: previous_plan[:year] }
          assumptions[:rolling_changes] = rolling_changes
        end

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
            reward_pct: reward_pct,
            debt_strategy: debt_strategy,
            assumptions: assumptions
          }
        )
      end

      private

      def base_source?(source)
        classification = source[:classification].presence
        return !VARIABLE_CLASSIFICATIONS.include?(classification) if classification.present?

        !source[:is_variable]
      end

      # Tasa de gasto discrecional según fase financiera.
      # Basado en metodologías CFP + Sethi CSP (ver specs/research/metodologias-coaching-financiero.md).
      # debt_payoff: restrictivo — cada peso libre va a deuda.
      # emergency_fund/investing/wealth_building: progresivamente más holgura.
      def discretionary_rate_for_phase(phase)
        case phase
        when "debt_payoff"    then 0.15
        when "emergency_fund" then 0.20
        when "investing"      then 0.25
        when "wealth_building" then 0.30
        else 0.15  # conservador si no hay fase configurada
        end
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

      def select_rolling_value(previous_plan, field, calculated, rolling_changes, rolling:)
        return calculated unless rolling

        inherited = previous_plan[field].to_i
        change_pct = percentage_change(inherited, calculated)
        rolling_changes << rolling_change_description(field, change_pct)
        return calculated if change_pct.nil?
        change_pct.abs <= 10 ? inherited : calculated
      end

      def percentage_change(previous, current)
        return 0 if previous.zero? && current.zero?
        return nil if previous.zero?

        (((current - previous).to_f / previous) * 100).round
      end

      def rolling_change_description(field, change_pct)
        return "#{field} cambió desde cero" if change_pct.nil?
        return "#{field} sin cambios" if change_pct.zero?

        direction = change_pct.positive? ? "aumentó" : "disminuyó"
        "#{field} #{direction} #{change_pct.abs}%"
      end

      def debt_linked_obligation?(obligation)
        obligation[:source_type] == "Debt"
      end
    end
  end
end
