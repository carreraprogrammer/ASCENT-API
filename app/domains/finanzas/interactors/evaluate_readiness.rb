module Finanzas
  module Interactors
    class EvaluateReadiness
      DIMENSION_WEIGHTS = {
        "transaction_history"   => 15,
        "categories"            => 10,
        "income_profile"        => 20,
        "recurring_obligations" => 15,
        "debts"                 => 10,
        "monthly_plan"          => 15,
        "behavioral_signals"    => 5,
        "streak_quality"        => 5,
        "closed_months"         => 5
      }.freeze

      SUFFICIENT_SCORE = 1.0
      PARTIAL_SCORE    = 0.5
      MISSING_SCORE    = 0.0

      def call(account_id:)
        progress = ::AccountProgress.find_or_initialize_by(account_id: account_id)
        return progress if progress.bypass_readiness?

        dimensions = evaluate_dimensions(account_id, progress)
        score = compute_score(dimensions)

        progress.readiness_score = score
        progress.save! if progress.persisted?

        { readiness_score: score, dimensions: dimensions, progress: progress }
      end

      private

      def evaluate_dimensions(account_id, progress)
        transactions = ::Transaction.where(account_id: account_id)
        income_sources = ::IncomeSource.active.where(account_id: account_id)
        recurring = ::RecurringObligation.active.where(account_id: account_id)
        debts = ::Debt.where(account_id: account_id)
        plans = ::MonthlyFinancialPlan.where(account_id: account_id)
        closed_plans = plans.where(status: "closed")

        {
          "transaction_history"   => transaction_history_state(transactions),
          "categories"            => categories_state(transactions),
          "income_profile"        => income_profile_state(income_sources),
          "recurring_obligations" => recurring_state(recurring),
          "debts"                 => debts_state(debts),
          "monthly_plan"          => monthly_plan_state(plans),
          "behavioral_signals"    => behavioral_signals_state(transactions),
          "streak_quality"        => streak_quality_state(progress),
          "closed_months"         => closed_months_state(closed_plans)
        }
      end

      def transaction_history_state(transactions)
        count = transactions.count
        if count >= 30
          "sufficient"
        elsif count >= 10
          "partial"
        else
          "missing"
        end
      end

      def categories_state(transactions)
        total = transactions.where(transaction_type: "expense", status: "confirmed").count
        return "missing" if total.zero?

        categorized = transactions
          .where(transaction_type: "expense", status: "confirmed")
          .where.not(subcategory_id: nil)
          .count

        ratio = categorized.to_f / total
        if ratio >= 0.8
          "sufficient"
        elsif ratio >= 0.4
          "partial"
        else
          "missing"
        end
      end

      def income_profile_state(income_sources)
        return "missing" if income_sources.empty?

        has_base = income_sources.any? { |s| s.classification == "base" || (!s.is_variable) }
        has_incomplete = income_sources.any? { |s| s.classification.blank? || s.cadence.blank? }

        if has_base && !has_incomplete
          "sufficient"
        else
          "partial"
        end
      end

      def recurring_state(recurring)
        recurring.any? ? "sufficient" : "partial"
      end

      def debts_state(debts)
        debts.any? ? "sufficient" : "partial"
      end

      def monthly_plan_state(plans)
        confirmed = plans.where(status: "confirmed")
        if confirmed.any?
          "sufficient"
        elsif plans.any?
          "partial"
        else
          "missing"
        end
      end

      def behavioral_signals_state(transactions)
        recent = transactions.where("created_at >= ?", 30.days.ago).count
        recent >= 10 ? "sufficient" : (recent >= 3 ? "partial" : "missing")
      end

      def streak_quality_state(progress)
        return "missing" unless progress.persisted?

        days = progress.streak_days || 0
        if days >= 30
          "sufficient"
        elsif days >= 7
          "partial"
        else
          "missing"
        end
      end

      def closed_months_state(closed_plans)
        count = closed_plans.count
        if count >= 3
          "sufficient"
        elsif count >= 1
          "partial"
        else
          "missing"
        end
      end

      def compute_score(dimensions)
        total_weight = DIMENSION_WEIGHTS.values.sum.to_f
        earned = dimensions.sum do |dim, state|
          weight = DIMENSION_WEIGHTS[dim] || 0
          multiplier = case state
                       when "sufficient" then SUFFICIENT_SCORE
                       when "partial"    then PARTIAL_SCORE
                       else                   MISSING_SCORE
                       end
          weight * multiplier
        end

        ((earned / total_weight) * 100).round(2)
      end
    end
  end
end
