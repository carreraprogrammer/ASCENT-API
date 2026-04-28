module Finanzas
  module Interactors
    # Fase C — Motor de detección estructural.
    #
    # Given a transaction being created/updated, tries to match it against:
    #   - recurring_obligations  (debt or regular recurring)
    #   - planned_expenses       (mandatory_one_off / irregular_maintenance)
    #
    # Returns a hash:
    #   { match_type: "debt|recurring|planned_expense|none",
    #     match_id:   Integer | nil,
    #     entity_name: String | nil,
    #     confidence: "high|medium|low|none" }
    #
    # Only "high" confidence matches should be auto-linked; others are surfaced
    # as suggestions for the user or agent to resolve.
    class DetectTransactionStructure
      RECURRING_AMOUNT_TOLERANCE = 0.05   # ±5 % of obligation amount
      PLANNED_AMOUNT_TOLERANCE   = 0.20   # ±20 % of planned expense
      DUE_DAY_WINDOW             = 5      # ± calendar days from due_day
      PLANNED_HORIZON_DAYS       = 90     # look-ahead window for target_date

      def call(account_id:, concept:, amount:, subcategory_id: nil, date_str: nil)
        amount = amount.to_i
        return no_match if amount <= 0

        day = parse_day(date_str)

        recurring = match_recurring(account_id, amount, subcategory_id, day)
        return recurring if recurring[:confidence] == "high"

        planned = match_planned(account_id, concept, amount)
        return planned if planned[:confidence] == "high"

        best_medium = [ recurring, planned ].max_by { |m| confidence_rank(m[:confidence]) }
        best_medium[:confidence] == "none" ? no_match : best_medium
      end

      private

      # ── Recurring obligations ─────────────────────────────────────────────

      def match_recurring(account_id, amount, subcategory_id, day)
        ::RecurringObligation.where(account_id: account_id, active: true).find_each do |ob|
          next unless within_pct?(ob.amount, amount, RECURRING_AMOUNT_TOLERANCE)

          subcat_match = subcategory_id.nil? || ob.subcategory_id.nil? || ob.subcategory_id == subcategory_id
          day_match    = day.nil? || ob.due_day.nil? || (ob.due_day - day).abs <= DUE_DAY_WINDOW
          confidence   = (subcat_match && day_match) ? "high" : "medium"

          type = ob.source_type == "Debt" ? "debt" : "recurring"
          return { match_type: type, match_id: ob.id, entity_name: ob.name, confidence: confidence }
        end

        no_match
      end

      # ── Planned expenses ──────────────────────────────────────────────────

      def match_planned(account_id, concept, amount)
        horizon = Date.current + PLANNED_HORIZON_DAYS

        expenses = ::PlannedExpense
          .where(account_id: account_id, status: "planned",
                 planning_type: %w[mandatory_one_off irregular_maintenance])
          .where("target_date <= ?", horizon)

        best = nil
        best_rank = 0

        expenses.find_each do |exp|
          amount_ok  = within_pct?(exp.amount_estimated, amount, PLANNED_AMOUNT_TOLERANCE)
          concept_ok = concept_overlap?(concept, exp.name)

          rank = (amount_ok ? 2 : 0) + (concept_ok ? 2 : 0)
          next if rank < 2

          confidence = rank >= 4 ? "high" : "medium"
          if confidence_rank(confidence) > best_rank
            best_rank = confidence_rank(confidence)
            best = { match_type: "planned_expense", match_id: exp.id,
                     entity_name: exp.name, confidence: confidence }
          end
        end

        best || no_match
      end

      # ── Helpers ───────────────────────────────────────────────────────────

      def within_pct?(base, actual, tolerance)
        base = base.to_f
        return false if base <= 0

        (base - actual.to_f).abs / base <= tolerance
      end

      def concept_overlap?(a, b)
        return false if a.blank? || b.blank?

        a_tokens = tokenize(a)
        b_tokens = tokenize(b)
        shared   = a_tokens & b_tokens
        shared.size >= 1 && shared.any? { |w| w.length >= 4 }
      end

      def tokenize(str)
        str.downcase
           .unicode_normalize(:nfd)
           .gsub(/\p{Mn}/, "")
           .gsub(/[^a-z0-9\s]/i, " ")
           .split
           .reject { |w| w.length < 3 }
      end

      def parse_day(date_str)
        return nil if date_str.blank?

        if date_str.match?(%r{\A\d{2}/\d{2}})
          date_str.split("/").first.to_i
        elsif date_str.match?(/\A\d{4}-\d{2}-\d{2}/)
          date_str.split("-").last.to_i
        end
      end

      def confidence_rank(conf)
        case conf
        when "high"   then 3
        when "medium" then 2
        when "low"    then 1
        else               0
        end
      end

      def no_match
        { match_type: "none", match_id: nil, entity_name: nil, confidence: "none" }
      end
    end
  end
end
