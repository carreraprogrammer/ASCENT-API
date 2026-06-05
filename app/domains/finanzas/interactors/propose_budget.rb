module Finanzas
  module Interactors
    class ProposeBudget
      # Reference ranges for Colombian users with no spending history (in COP)
      COLOMBIAN_RANGES = {
        "housing"              => { min: 800_000,  max: 2_500_000, hint: "Arriendo promedio estrato 3-4" },
        "utilities"            => { min: 100_000,  max: 350_000,   hint: "Internet, celular, servicios" },
        "groceries"            => { min: 350_000,  max: 600_000,   hint: "Mercado mensual, 1 persona" },
        "dining_out"           => { min: 80_000,   max: 300_000,   hint: "Restaurantes y deliveries" },
        "transportation"       => { min: 80_000,   max: 400_000,   hint: "Gasolina, Uber, bus, peajes" },
        "vehicle_maintenance"  => { min: 80_000,   max: 250_000,   hint: "Mantenimiento vehículo" },
        "health"               => { min: 50_000,   max: 200_000,   hint: "Médico, farmacia, EPS" },
        "personal_care"        => { min: 30_000,   max: 150_000,   hint: "Barbería, gimnasio, estética" },
        "entertainment"        => { min: 50_000,   max: 200_000,   hint: "Streaming, salidas, eventos" },
        "education"            => { min: 30_000,   max: 300_000,   hint: "Cursos, libros, suscripciones" },
        "savings_emergency"    => { min: 100_000,  max: 500_000,   hint: "Fondo de emergencia (3-6 meses de gastos)" }
      }.freeze

      def initialize(
        ctx_builder: Finanzas::Interactors::BuildBudgetContext.new,
        plan_repo: Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      )
        @ctx_builder = ctx_builder
        @plan_repo = plan_repo
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
        has_history       = ctx[:spending_history].any?

        # Phase-aware: reserve surplus for the user's goal before distributing to discretionary.
        # This ensures the plan reflects the financial objective, not just historical spending.
        phase           = ctx.dig(:financial_context, :phase)
        reward_pct      = ctx.dig(:financial_context, :reward_pct).to_f
        surplus_target  = compute_surplus_target(phase, reward_pct, planning_income, free_margin)
        effective_margin = [ free_margin - surplus_target, 0 ].max

        closed_plans = @plan_repo.last_closed(account_id: account_id, limit: 3)
        last_plan_budgets = extract_last_plan_budgets(closed_plans.first)
        categories, available = build_categories(ctx, effective_margin, has_history, last_plan_budgets)
        historical_patterns = extract_patterns(closed_plans)

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
          planned_expenses:     ctx[:planned_expenses],
          sinking_funds:        ctx[:sinking_funds],
          categories:           categories,
          available_categories: available,
          free_margin:          free_margin,
          effective_margin:     effective_margin,
          surplus_target:       surplus_target,
          surplus_target_label: surplus_target_label(phase),
          phase:                phase,
          has_history:          has_history,
          mode:                 has_history ? "data_driven" : "provisional",
          warnings:             build_warnings(ctx, free_margin, has_history),
          historical_patterns:  historical_patterns,
          existing_plan:        ctx[:existing_plan],
          month:                month,
          year:                 year
        }
      end

      private

      def build_categories(ctx, free_margin, has_history, last_plan_budgets = {})
        obligated_codes = ctx[:obligations][:by_category].keys.map(&:to_s)
        cat_map = ctx[:budget_categories].index_by { |bc| bc[:code].to_s }

        if has_history
          build_from_history(ctx, cat_map, obligated_codes, free_margin, last_plan_budgets)
        else
          build_from_ranges(cat_map, obligated_codes)
        end
      end

      def build_from_history(ctx, cat_map, obligated_codes, free_margin, last_plan_budgets = {})
        history = ctx[:spending_history].reject { |code, _| obligated_codes.include?(code.to_s) }

        suggestions = history.map do |code, data|
          cat           = cat_map[code.to_s]
          range         = COLOMBIAN_RANGES[code.to_s]
          avg           = data[:average_monthly]
          last_budgeted = last_plan_budgets[code.to_s]
          overspent     = last_budgeted.present? && avg > last_budgeted

          {
            code:             code.to_s,
            name:             cat&.dig(:name) || code.to_s.humanize,
            category_type:    cat&.dig(:category_type) || "necessary",
            suggested_amount: overspent ? last_budgeted : avg,
            avg_spent:        avg,
            last_budgeted:    last_budgeted,
            overspent:        overspent,
            overspend_pct:    overspent ? ((avg - last_budgeted).to_f / last_budgeted * 100).round : nil,
            months_with_data: data[:months_with_data],
            range_hint:       range ? "Rango referencia: #{format_cop(range[:min])}–#{format_cop(range[:max])}" : nil
          }
        end.sort_by { |c| -c[:suggested_amount] }

        history_total = suggestions.sum { |c| c[:suggested_amount] }
        if history_total > free_margin && free_margin > 0
          scale = free_margin.to_f / history_total
          suggestions = suggestions.map { |c| c.merge(suggested_amount: round_to_thousands((c[:suggested_amount] * scale).round)) }
        end

        proposed_codes = suggestions.map { |c| c[:code] }.to_set | obligated_codes.to_set
        available = build_available(cat_map, proposed_codes)

        [ suggestions, available ]
      end

      def build_from_ranges(cat_map, obligated_codes)
        # No history: propose all known categories with amount=0 and range hints
        suggested_codes = COLOMBIAN_RANGES.keys - obligated_codes

        suggestions = suggested_codes.map do |code|
          cat   = cat_map[code]
          range = COLOMBIAN_RANGES[code]
          {
            code:             code,
            name:             cat&.dig(:name) || code.humanize,
            category_type:    cat&.dig(:category_type) || "necessary",
            suggested_amount: 0,
            avg_spent:        nil,
            months_with_data: 0,
            range_hint:       "#{range[:hint]} · #{format_cop(range[:min])}–#{format_cop(range[:max])}"
          }
        end

        proposed_codes = (suggested_codes + obligated_codes).to_set
        available = build_available(cat_map, proposed_codes)

        [ suggestions, available ]
      end

      def build_available(cat_map, proposed_codes)
        cat_map.values
          .reject { |bc| proposed_codes.include?(bc[:code].to_s) }
          .map do |bc|
            range = COLOMBIAN_RANGES[bc[:code].to_s]
            {
              code:          bc[:code].to_s,
              name:          bc[:name],
              category_type: bc[:category_type],
              range_hint:    range ? "#{range[:hint]} · #{format_cop(range[:min])}–#{format_cop(range[:max])}" : nil
            }
          end
      end

      def compute_surplus_target(phase, reward_pct, income, free_margin)
        return 0 unless %w[debt_payoff emergency_fund].include?(phase.to_s)
        return 0 if free_margin <= 0

        rate   = reward_pct > 0 ? (reward_pct / 100.0) : 0.10
        target = (income * rate).round
        round_to_thousands([ target, free_margin ].min)
      end

      def surplus_target_label(phase)
        case phase.to_s
        when "debt_payoff"     then "Reservado para pago extra de deuda"
        when "emergency_fund"  then "Reservado para fondo de emergencia"
        end
      end

      def build_warnings(ctx, free_margin, has_history)
        [].tap do |w|
          w << "Sin fuentes de ingreso registradas — agrega tus ingresos primero" if ctx[:gaps][:missing_income]
          w << "Sin obligaciones recurrentes — el plan podría estar incompleto" if ctx[:gaps][:missing_obligations]
          w << "Margen libre negativo — las obligaciones y deudas superan el ingreso base" if free_margin < 0
          w << "Las obligaciones parecen bajas (menos del 15% del ingreso)" if ctx[:gaps][:obligations_seem_low]
          w << "Sin historial de gastos — los montos son estimados. Revisá el plan después del primer mes." if !has_history
        end
      end

      def extract_last_plan_budgets(plan)
        return {} if plan.nil?

        categories = plan.dig(:execution_snapshot, "categories") ||
                     plan.dig(:execution_snapshot, :categories) ||
                     []

        categories.each_with_object({}) do |cat, hash|
          code     = cat["code"] || cat[:code]
          budgeted = (cat["budgeted"] || cat[:budgeted]).to_i
          hash[code.to_s] = budgeted if code.present? && budgeted > 0
        end
      end

      def extract_patterns(closed_plans)
        return [] if closed_plans.blank?

        category_patterns(closed_plans) + income_patterns(closed_plans)
      end

      def category_patterns(closed_plans)
        category_rows = Hash.new { |hash, code| hash[code] = { name: nil, variances: [] } }

        closed_plans.each do |plan|
          categories = plan.dig(:execution_snapshot, "categories") ||
                       plan.dig(:execution_snapshot, :categories) ||
                       []

          categories.each do |category|
            code = category["code"] || category[:code]
            next if code.blank?

            variance_pct = category["variance_pct"] || category[:variance_pct]
            next if variance_pct.nil?

            row = category_rows[code.to_s]
            row[:name] ||= category["name"] || category[:name]
            row[:variances] << variance_pct.to_i
          end
        end

        category_rows.filter_map do |code, row|
          over_count = row[:variances].count { |variance| variance > 15 }
          next if over_count < 2

          avg_variance_pct = average(row[:variances])
          {
            pattern: "consistently_over",
            category_code: code,
            category_name: row[:name],
            avg_variance_pct: avg_variance_pct,
            months_checked: row[:variances].size,
            suggestion: "En los últimos #{row[:variances].size} meses esta categoría superó el plan de forma recurrente; revisá subir el límite o ajustar el gasto."
          }
        end
      end

      def income_patterns(closed_plans)
        shortfalls = closed_plans.filter_map do |plan|
          base_budget_income = plan[:base_budget_income].to_i
          income_actual = plan[:income_actual].to_i
          next if base_budget_income <= 0
          next unless income_actual < (base_budget_income * 0.95)

          base_budget_income - income_actual
        end

        return [] if shortfalls.size < 2

        [
          {
            pattern: "income_overestimated",
            category_code: nil,
            avg_shortfall: average(shortfalls),
            months_checked: closed_plans.size,
            suggestion: "Tu ingreso real quedó por debajo del plan en #{shortfalls.size} de los últimos #{closed_plans.size} meses; conviene planear con una base más conservadora."
          }
        ]
      end

      def average(values)
        (values.sum.to_f / values.size).round
      end

      def round_to_thousands(amount)
        ((amount.to_f / 1000).round * 1000).to_i
      end

      def format_cop(amount)
        "$#{(amount / 1000).round}k"
      end
    end
  end
end
