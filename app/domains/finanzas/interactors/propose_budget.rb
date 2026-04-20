module Finanzas
  module Interactors
    class ProposeBudget
      def initialize(ctx_builder: Finanzas::Interactors::BuildBudgetContext.new)
        @ctx_builder = ctx_builder
      end

      def call(account_id:, month:, year:, include_variable: false)
        ctx = @ctx_builder.call(account_id: account_id, month: month, year: year)

        income            = ctx[:income]
        planning_income   = income[:fixed_total] + (include_variable ? income[:variable_projection] : 0)
        obligations_total = ctx[:obligations][:total]
        debt_total        = ctx[:debt_minimums][:total]
        sinking_total     = ctx[:sinking_funds].sum { |sf| sf[:monthly_contribution].to_i }
        committed_total   = obligations_total + debt_total + sinking_total
        free_margin       = planning_income - committed_total

        categories = build_categories(ctx, free_margin)

        {
          income: {
            fixed_total:         income[:fixed_total],
            variable_projection: income[:variable_projection],
            planning_income:     planning_income,
            include_variable:    include_variable,
            fixed_sources:       income[:fixed_sources],
            variable_sources:    income[:variable_sources]
          },
          committed: {
            obligations_total:   obligations_total,
            debt_minimums_total: debt_total,
            sinking_funds_total: sinking_total,
            total:               committed_total,
            by_category:         ctx[:obligations][:by_category]
          },
          sinking_funds: ctx[:sinking_funds],
          categories:    categories,
          free_margin:   free_margin,
          warnings:      build_warnings(ctx, free_margin),
          existing_plan: ctx[:existing_plan],
          month:         month,
          year:          year
        }
      end

      private

      def build_categories(ctx, free_margin)
        # Codes already committed through obligations — skip them
        obligated_codes = ctx[:obligations][:by_category].keys.map(&:to_s)
        cat_map = ctx[:budget_categories].index_by { |bc| bc[:code].to_s }
        history = ctx[:spending_history].reject { |code, _| obligated_codes.include?(code.to_s) }

        suggestions = history.map do |code, data|
          cat = cat_map[code.to_s]
          {
            code:              code.to_s,
            name:              cat&.dig(:name) || code.to_s.humanize,
            category_type:     cat&.dig(:category_type) || "necessary",
            suggested_amount:  data[:average_monthly],
            avg_spent:         data[:average_monthly],
            months_with_data:  data[:months_with_data]
          }
        end.sort_by { |c| -c[:suggested_amount] }

        history_total = suggestions.sum { |c| c[:suggested_amount] }
        return suggestions if history_total == 0 || free_margin <= 0 || history_total <= free_margin

        scale = free_margin.to_f / history_total
        suggestions.map { |c| c.merge(suggested_amount: round_to_thousands((c[:suggested_amount] * scale).round)) }
      end

      def build_warnings(ctx, free_margin)
        [].tap do |w|
          w << "Sin fuentes de ingreso registradas — agrega tus ingresos primero" if ctx[:gaps][:missing_income]
          w << "Sin obligaciones recurrentes — el plan podría estar incompleto" if ctx[:gaps][:missing_obligations]
          w << "Margen libre negativo — las obligaciones y deudas superan el ingreso base" if free_margin < 0
          w << "Las obligaciones parecen bajas (menos del 15% del ingreso)" if ctx[:gaps][:obligations_seem_low]
        end
      end

      def round_to_thousands(amount)
        ((amount.to_f / 1000).round * 1000).to_i
      end
    end
  end
end
