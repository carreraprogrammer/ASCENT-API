module Finanzas
  module Interactors
    class BackfillRecurringObligationSources
      Result = Struct.new(:linked, :already_linked, :ambiguous, :skipped, keyword_init: true)

      def call(scope: ::RecurringObligation.all)
        result = Result.new(linked: [], already_linked: [], ambiguous: [], skipped: [])

        scope.includes(:account, :user).find_each do |obligation|
          process_obligation(obligation, result)
        end

        result
      end

      private

      def process_obligation(obligation, result)
        if obligation.source_type.present? || obligation.source_id.present?
          result.already_linked << build_reference(obligation)
          return
        end

        candidates = debt_candidates_for(obligation)
        if candidates.none?
          result.skipped << build_reference(obligation).merge(reason: "no_confident_match")
          return
        end

        if candidates.size > 1
          result.ambiguous << build_reference(obligation).merge(
            reason: "multiple_confident_matches",
            candidate_debt_ids: candidates.map(&:id)
          )
          return
        end

        debt = candidates.first
        unless obligation.subcategory&.code == "creditos"
          result.skipped << build_reference(obligation).merge(reason: "requires_credit_subcategory")
          return
        end

        obligation.update!(source_type: "Debt", source_id: debt.id)
        result.linked << build_reference(obligation).merge(debt_id: debt.id, debt_name: debt.name)
      end

      def debt_candidates_for(obligation)
        return [] if obligation.amount.to_i <= 0

        debts = ::Debt.active
        debts = debts.where(account_id: obligation.account_id) if obligation.account_id.present?
        debts = debts.where(user_id: obligation.user_id) if obligation.user_id.present?
        debts = debts.where(monthly_payment: obligation.amount)

        normalized_name = normalize_name(obligation.name)
        return [] if normalized_name.blank?

        debts.select do |debt|
          debt_name = normalize_name(debt.name)
          debt_name.present? && (debt_name == normalized_name || debt_name.include?(normalized_name) || normalized_name.include?(debt_name))
        end
      end

      def normalize_name(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
      end

      def build_reference(obligation)
        {
          recurring_obligation_id: obligation.id,
          recurring_obligation_name: obligation.name
        }
      end
    end
  end
end
