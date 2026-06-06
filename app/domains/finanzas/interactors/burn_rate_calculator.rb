module Finanzas
  module Interactors
    # Calcula el burn rate del mes por categoría presupuestada.
    #
    # Responde: "¿A qué ritmo voy gastando y a dónde llego a fin de mes?"
    #
    # Extraído de SummaryController para permitir testing independiente y reutilización.
    # La lógica de comportamiento por tipo de categoría (variable_linear, fixed_once, etc.)
    # vive aquí — es la base del coaching de presupuesto del agente.
    class BurnRateCalculator
      # @param account_id [Integer]
      # @param month      [Integer]
      # @param year       [Integer]
      # @param budgets    [Array<Hash>]  resultado de BudgetRepository#for_month
      # @param today      [Date]
      # @return [Hash, nil]  nil si no hay presupuestos configurados
      def call(account_id:, month:, year:, budgets:, today:)
        return nil if budgets.empty?

        days_in_month = Date.new(year, month, -1).day
        days_elapsed  = [ today.day, days_in_month ].min

        spent_by_cat   = load_spent_by_category(account_id, month, year)
        subcat_by_cat  = load_subcategory_breakdown(account_id, month, year)
        budget_by_cat  = group_budgets_by_category(budgets)
        budget_by_subcat = budget_by_subcategory(budgets)

        categories = budget_by_cat.map do |cat_id, cat|
          spent    = spent_by_cat[cat_id].to_i
          budget   = cat[:amount_limit]
          behavior = financial_behavior_for(
            category_type: cat[:category_type],
            name:          cat[:category_name]
          )
          projected = days_elapsed > 0 ? (spent.to_f / days_elapsed * days_in_month).round : 0
          pct       = budget > 0 ? (projected.to_f / budget * 100).round : 0
          primary   = category_primary_metric(
            behavior:      behavior,
            name:          cat[:category_name],
            budget:        budget,
            spent:         spent,
            projected:     projected,
            days_elapsed:  days_elapsed,
            days_in_month: days_in_month
          )

          {
            category:       cat[:category_name],
            category_type:  cat[:category_type],
            category_id:    cat_id,
            budget:         budget,
            spent:          spent,
            projected:      projected,
            pct:            pct,
            behavior:       behavior,
            primary_metric: primary,
            on_track:       primary[:status] != "critical",
            alert:          %w[warning critical].include?(primary[:status]) ? primary[:body] : nil,
            subcategories:  (subcat_by_cat[cat_id] || []).map { |r|
              r.merge(budget: budget_by_subcat.fetch(r[:subcategory_id], 0))
            }
          }
        end

        { days_elapsed: days_elapsed, days_in_month: days_in_month, categories: categories }
      end

      private

      # ── Queries ──────────────────────────────────────────────────────────────

      def load_spent_by_category(account_id, month, year)
        expense_transactions_for_budget_period(account_id, month, year)
          .reject { |transaction| transaction.category_id.nil? }
          .group_by(&:category_id)
          .transform_values { |transactions| transactions.sum { |transaction| transaction.amount.to_i } }
      end

      def load_subcategory_breakdown(account_id, month, year)
        expense_transactions_for_budget_period(account_id, month, year)
          .reject { |transaction| transaction.subcategory_id.nil? }
          .group_by { |transaction| [ transaction.category_id, transaction.subcategory_id, transaction.subcategory&.name ] }
          .map { |(cat_id, sub_id, sub_name), transactions|
            {
              category_id: cat_id,
              subcategory_id: sub_id,
              subcategory: sub_name,
              spent: transactions.sum { |transaction| transaction.amount.to_i }
            }
          }
          .group_by { |r| r[:category_id] }
      end

      def expense_transactions_for_budget_period(account_id, month, year)
        period = Date.new(year.to_i, month.to_i, 1)

        ::Transaction
          .includes(:subcategory)
          .where(account_id: account_id, transaction_type: "expense")
          .where(status: %w[confirmed pending])
          .where(sinking_fund_id: nil)
          .select { |transaction| transaction_applies_to_period?(transaction, period) }
      end

      def transaction_applies_to_period?(transaction, period)
        if transaction.covers_period_month.present? && transaction.covers_period_year.present?
          return transaction.covers_period_month.to_i == period.month &&
            transaction.covers_period_year.to_i == period.year
        end

        data = (transaction.metadata || {}).to_h.stringify_keys
        explicit_period = data["applies_to_period"].presence
        return explicit_period == period.strftime("%Y-%m") if explicit_period

        explicit_month = data["applies_to_month"].presence
        explicit_year = data["applies_to_year"].presence
        if explicit_month && explicit_year
          return explicit_month.to_i == period.month && explicit_year.to_i == period.year
        end

        transaction.month.to_i == period.month && transaction.year.to_i == period.year
      end

      def group_budgets_by_category(budgets)
        budgets
          .reject { |b| b[:category_id].nil? }
          .group_by { |b| b[:category_id] }
          .transform_values do |rows|
            {
              category_name: rows.first[:category_name],
              category_type: rows.first[:category_type],
              amount_limit:  rows.sum { |b| b[:amount_limit].to_i }
            }
          end
      end

      def budget_by_subcategory(budgets)
        budgets
          .reject { |b| b[:subcategory_id].nil? }
          .each_with_object({}) { |b, h| h[b[:subcategory_id]] = b[:amount_limit].to_i }
      end

      # ── Clasificación de comportamiento ──────────────────────────────────────
      # Determina cómo se mide y alerta esta categoría según su naturaleza.

      def financial_behavior_for(category_type:, name: nil)
        text = [ category_type, name ].compact.join(" ").downcase

        return "debt_payment" if text.match?(/debt|deuda|credit|cr[eé]dito|prestamo|pr[eé]stamo|loan|tarjeta/)
        return "savings_goal" if text.match?(/saving|savings|ahorro|inversi[oó]n|investment|fondo|emergencia/)
        return "fixed_once"   if text.match?(/rent|arriendo|alquiler|seguro|insurance|predial|matr[ií]cula/)
        return "fixed_recurring" if text.match?(/subscription|suscrip|netflix|spotify|internet|celular|phone|gimnasio|gym|servicio|utility|utilities/)
        return "variable_spiky"  if text.match?(/health|salud|ropa|regalo|gift|reparaci[oó]n|repair|imprevisto|travel|viaje/)
        return "variable_linear" if text.match?(/food|comida|groceries|mercado|transport|transporte|dining|domicilio|restaurant|cafe|caf[eé]|snack|salida/)

        case category_type.to_s
        when "committed"    then "fixed_recurring"
        when "necessary", "discretionary", "social" then "variable_linear"
        when "investment"   then "savings_goal"
        else "variable_spiky"
        end
      end

      # ── Métrica principal por comportamiento ─────────────────────────────────

      def category_primary_metric(behavior:, name:, budget:, spent:, projected:, days_elapsed:, days_in_month:)
        ratio         = budget.to_i.positive? ? spent.to_f / budget.to_i : 0
        projected_over = projected.to_i - budget.to_i

        case behavior
        when "variable_linear"
          progress = month_progress_ratio(days_elapsed, days_in_month)
          status = if budget.to_i.positive? && projected > budget
                     "critical"
                   elsif budget.to_i.positive? && ratio >= progress + 0.2
                     "warning"
                   else
                     "comfortable"
                   end
          {
            kind:   "month_end_projection",
            status: status,
            title:  status == "critical" ? "Vas más rápido de lo planeado" : "Estimado a fin de mes",
            body:   projected_over.positive? ?
              "A este ritmo cerrarías #{format_cop(projected_over)} por encima del presupuesto." :
              "A este ritmo cerrarías dentro del presupuesto.",
            value:  projected,
            budget: budget
          }

        when "fixed_once", "fixed_recurring"
          pending = [ budget.to_i - spent.to_i, 0 ].max
          status  = pending.positive? ? "warning" : "comfortable"
          {
            kind:   "payment_status",
            status: status,
            title:  pending.positive? ? "Pago pendiente" : "Pago cubierto",
            body:   pending.positive? ?
              "Aún faltan #{format_cop(pending)} por cubrir en #{name}." :
              "#{name} ya está cubierto este mes.",
            value:  pending,
            budget: budget
          }

        when "savings_goal"
          pct = budget.to_i.positive? ? ((spent.to_f / budget.to_i) * 100).round : 0
          {
            kind:   "goal_progress",
            status: pct >= 100 ? "comfortable" : pct >= 60 ? "warning" : "critical",
            title:  "Avance de meta",
            body:   "Llevas #{pct}% de la meta mensual.",
            value:  pct,
            budget: budget
          }

        when "debt_payment"
          pct = budget.to_i.positive? ? ((spent.to_f / budget.to_i) * 100).round : 0
          {
            kind:   "debt_progress",
            status: spent.to_i.positive? ? "comfortable" : "warning",
            title:  spent.to_i.positive? ? "Pago a deuda registrado" : "Pago pendiente",
            body:   spent.to_i.positive? ?
              "Este pago ayuda a reducir deuda y sostiene tu plan." :
              "Todavía no hay pago registrado para esta deuda.",
            value:  pct,
            budget: budget
          }

        else
          pct    = budget.to_i.positive? ? ((spent.to_f / budget.to_i) * 100).round : 0
          status = pct >= 100 ? "critical" : pct >= 70 ? "warning" : "comfortable"
          {
            kind:   "spiky_context",
            status: status,
            title:  status == "comfortable" ? "Gasto puntual bajo control" : "Gasto puntual relevante",
            body:   "Este gasto consumió #{pct}% del presupuesto asignado.",
            value:  pct,
            budget: budget
          }
        end
      end

      def month_progress_ratio(days_elapsed, days_in_month)
        return 0 if days_in_month.to_i <= 0

        days_elapsed.to_f / days_in_month.to_i
      end

      def format_cop(amount)
        "$#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse}"
      end
    end
  end
end
