module Finanzas
  module Interactors
    # Fase C — Motor de detección estructural.
    #
    # Given a transaction being created/updated, tries to match it against:
    #   - recurring_obligations  (debt or regular recurring)
    #   - sinking_funds          (monthly contributions to pockets)
    #   - planned_expenses       (mandatory_one_off / irregular_maintenance)
    #
    # Returns a hash:
    #   { match_type: "debt|recurring|savings_goal|sinking_fund|planned_expense|none",
    #     match_id:   Integer | nil,
    #     entity_name: String | nil,
    #     confidence: "high|medium|low|none" }
    #
    # Only "high" confidence matches should be auto-linked; others are surfaced
    # as suggestions for the user or agent to resolve.
    class DetectTransactionStructure
      RECURRING_AMOUNT_TOLERANCE_TIGHT = 0.05   # ±5 % — amount-only matching (no concept signal)
      RECURRING_AMOUNT_TOLERANCE_LOOSE = 0.40   # ±40 % — concept-anchored (FX, discounts, estimates)
      SINKING_AMOUNT_TOLERANCE         = 0.20   # ±20 % of monthly contribution
      PLANNED_AMOUNT_TOLERANCE         = 0.20   # ±20 % of planned expense
      DUE_DAY_WINDOW                   = 5      # ± calendar days from due_day
      PLANNED_HORIZON_DAYS             = 90     # look-ahead window for target_date

      def call(account_id:, concept:, amount:, subcategory_id: nil, date_str: nil)
        amount = amount.to_i
        return no_match if amount <= 0

        day = parse_day(date_str)

        recurring = match_recurring(account_id, concept, amount, subcategory_id, day)
        return recurring if recurring[:confidence] == "high"

        sinking = match_sinking_fund(account_id, concept, amount)
        return sinking if sinking[:confidence] == "high"

        planned = match_planned(account_id, concept, amount)
        return planned if planned[:confidence] == "high"

        best_medium = [ recurring, sinking, planned ].max_by { |m| confidence_rank(m[:confidence]) }
        best_medium[:confidence] == "none" ? no_match : best_medium
      end

      private

      # ── Recurring obligations ─────────────────────────────────────────────

      def match_recurring(account_id, concept, amount, subcategory_id, day)
        matches = []

        ::RecurringObligation.where(account_id: account_id, active: true).find_each do |ob|
          concept_match = concept_overlap?(concept, ob.name)

          # Concept anchors a loose amount window (FX, discounts, estimates).
          # Without concept signal we require a tight amount match to avoid noise.
          effective_tolerance = concept_match ? RECURRING_AMOUNT_TOLERANCE_LOOSE : RECURRING_AMOUNT_TOLERANCE_TIGHT
          amount_match = within_pct?(ob.amount, amount, effective_tolerance)
          amount_exact = ob.amount.to_i == amount

          next unless concept_match || amount_match

          # La subcategoría es señal POSITIVA-only: si coincide suma confianza; si choca
          # se ignora (no veta). El auto-categorizador del banco adivina la gaveta y un
          # error suyo no debe matar un match de monto+día (caso PILA: subcat 9 vs 3).
          subcat_agrees = subcategory_id.present? && ob.subcategory_id.present? &&
                          ob.subcategory_id == subcategory_id
          day_known     = day.present? && ob.due_day.present?
          day_match     = day_known && (ob.due_day - day).abs <= DUE_DAY_WINDOW
          score         = 0
          score        += 40 if concept_match
          score        += 25 if amount_exact
          score        += 20 if amount_match && within_pct?(ob.amount, amount, RECURRING_AMOUNT_TOLERANCE_TIGHT)
          score        += 10 if amount_match
          score        += 10 if subcat_agrees
          score        += 10 if day_match
          confidence    = recurring_confidence(
            concept_match: concept_match, amount_match: amount_match,
            amount_exact: amount_exact, subcat_agrees: subcat_agrees, day_match: day_match
          )
          type = case ob.source_type
                 when "Debt"        then "debt"
                 when "SavingsGoal" then "savings_goal"
                 else                    "recurring"
                 end
          matches << {
            match_type: type,
            match_id: ob.id,
            entity_name: ob.name,
            confidence: confidence,
            score: score
          }
        end

        best = matches.max_by { |match| [ confidence_rank(match[:confidence]), match[:score] ] }
        return no_match unless best

        # Un empate en la cima (misma confianza + score) es ambiguo: no auto-vinculamos
        # ni siquiera en high, porque con el auto-link por monto exacto dos obligaciones
        # de igual monto/día podrían colisionar y linkear la equivocada (y en deudas eso
        # mueve saldos).
        tied_best = matches.count do |match|
          match[:confidence] == best[:confidence] && match[:score] == best[:score]
        end
        return no_match if tied_best > 1

        best.except(:score)
      end

      # ── Sinking funds ────────────────────────────────────────────────────

      def match_sinking_fund(account_id, concept, amount)
        matches = []

        ::SinkingFund.where(account_id: account_id, active: true).find_each do |fund|
          concept_match = concept_overlap?(concept, fund.name)
          amount_match = fund.monthly_contribution.to_i.positive? &&
                         within_pct?(fund.monthly_contribution, amount, SINKING_AMOUNT_TOLERANCE)
          next unless concept_match || amount_match

          score = 0
          score += 30 if concept_match
          score += 20 if amount_match
          confidence = concept_match && amount_match ? "high" : "medium"

          matches << {
            match_type: "sinking_fund",
            match_id: fund.id,
            entity_name: fund.name,
            confidence: confidence,
            score: score
          }
        end

        best = matches.max_by { |match| [ confidence_rank(match[:confidence]), match[:score] ] }
        return no_match unless best

        tied_best = matches.count do |match|
          match[:confidence] == best[:confidence] && match[:score] == best[:score]
        end
        return no_match if tied_best > 1 && best[:confidence] != "high"

        best.except(:score)
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

      def recurring_confidence(concept_match:, amount_match:, amount_exact:, subcat_agrees:, day_match:)
        # Concept + amount within loose tolerance → auto-link (FX, discounts, estimates).
        return "high" if concept_match && amount_match
        # Concept + confirmed structure → high even if amount differs.
        return "high" if concept_match && subcat_agrees && day_match
        # Monto EXACTO al peso, anclado por día o subcategoría → auto-link sin concepto.
        # El extracto bancario casi nunca cruza textualmente con el nombre de la obligación
        # ("Pago Planilla Unica…" vs "PILA Freelance"), pero un monto idéntico al peso en la
        # ventana de vencimiento es evidencia fuerte.
        return "high" if amount_exact && (day_match || subcat_agrees)
        # Monto dentro de tolerancia + una señal estructural confirmada.
        return "high" if amount_match && subcat_agrees && day_match
        # Señales sueltas: prometedoras pero piden confirmación humana/del agente.
        return "medium" if concept_match
        return "medium" if amount_match && (subcat_agrees || day_match)
        return "medium" if amount_exact

        "low"
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
