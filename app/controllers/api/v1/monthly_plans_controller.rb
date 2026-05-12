module Api
  module V1
    class MonthlyPlansController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("budgets:read")

        result = repo.list_history(
          account_id: current_account.id,
          page: (params[:page] || 1).to_i,
          per_page: (params[:per_page] || 12).to_i
        )
        render json: result
      end

      def current
        return unless require_scope!("budgets:read")

        plan = current_plan
        return render json: { data: nil } unless plan

        render json: { data: build_current_plan_response(plan) }
      end

      def wizard_data
        return unless require_scope!("budgets:read")

        data = Finanzas::Interactors::WizardData.new.call(
          account_id: current_account.id,
          user_id: current_owner_user_id,
          month: plan_month,
          year: plan_year
        )
        render json: { data: data }
      rescue => e
        render_unprocessable(e.message)
      end

      def propose
        return unless require_scope!("budgets:read")
        proposal = Finanzas::Interactors::ProposeBudget.new.call(
          account_id:       current_account.id,
          month:            plan_month,
          year:             plan_year,
          include_variable: ActiveModel::Type::Boolean.new.cast(params[:include_variable])
        )
        render json: { data: proposal }
      rescue => e
        render_unprocessable(e.message)
      end

      def generate
        return unless require_scope!("budgets:create")
        plan = Finanzas::Interactors::GenerateMonthlyFinancialPlan.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          month: plan_month,
          year: plan_year,
          mode: params[:mode].presence || "conservative"
        )
        render json: { data: plan }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def confirm
        return unless require_scope!("budgets:update")
        plan = repo.update(
          params[:id],
          plan_update_params.merge(status: "confirmed", confirmed_at: Time.current),
          account_id: current_account.id
        )

        if params[:lines].present?
          # Wizard flow: lines = [{ subcategory_code:, amount: }]
          # Delete all existing budgets for the period first so stale category-level
          # records from the legacy flow don't persist alongside the new subcategory-level
          # ones and create duplicate/doubled totals in the plan view.
          ::Budget.where(
            account_id: current_account.id,
            month: plan[:month],
            year: plan[:year]
          ).delete_all

          resolved = resolve_wizard_lines(params[:lines])
          budget_repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: plan[:month],
            year: plan[:year],
            budgets: resolved
          )
        elsif params[:budgets].present?
          # Legacy flow: budgets = [{ category_id:, amount_limit: }]
          budget_repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: plan[:month],
            year: plan[:year],
            budgets: params[:budgets].map { |b| b.permit(:category_id, :amount_limit).to_h.symbolize_keys }
          )
        end

        EventBus.publish("xp.plan_confirmed", account_id: current_account.id, plan_id: plan[:id])
        render json: { data: plan }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue Finanzas::Errors::InvalidBudgetLine => e
        render json: { errors: [ { status: "422", detail: e.message } ] }, status: :unprocessable_entity
      rescue => e
        render_unprocessable(e.message)
      end

      def close
        return unless require_scope!("budgets:update")

        plan = Finanzas::Interactors::CloseMonthlyPlan.new.call(
          account_id: current_account.id,
          plan_id: params[:id].to_i
        )
        render json: { data: plan }
      rescue Finanzas::Errors::PlanNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue Finanzas::Errors::PlanNotConfirmed => e
        render json: { errors: [ { status: "422", detail: e.message } ] }, status: :unprocessable_entity
      end

      def update
        return unless require_scope!("budgets:update")
        plan = repo.update(params[:id], plan_update_params, account_id: current_account.id)
        render json: { data: plan }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      end

      def budget_repo
        @budget_repo ||= Finanzas::Repositories::BudgetRepository.new
      end

      def current_plan
        repo.find_for_month(account_id: current_account.id, month: plan_month, year: plan_year)
      end

      def plan_month
        (params[:month] || Time.now.month).to_i
      end

      def plan_year
        (params[:year] || Time.now.year).to_i
      end

      def plan_update_params
        params.permit(
          :mode, :base_budget_income, :expected_variable_income,
          :recurring_obligations_total, :debt_minimums_total,
          :protected_buffer_amount, :discretionary_limit,
          :overflow_rule, :reward_pct, :investment_target, :debt_strategy,
          overflow_rule_detail: {}, assumptions: {}
        ).to_h.symbolize_keys
      end

      # Resolves wizard lines ([{ subcategory_code:, amount: }]) into budget attrs
      # ([{ category_id:, subcategory_id:, amount_limit: }]) suitable for
      # BudgetRepository#upsert_bulk.
      #
      # Now that Budget has a subcategory_id column each line is stored at subcategory
      # granularity so amounts are NOT aggregated.  The unique index on
      # (account_id, subcategory_id, month, year) WHERE subcategory_id IS NOT NULL
      # guarantees idempotency.
      def resolve_wizard_lines(raw_lines)
        codes = raw_lines.map { |l| l[:subcategory_code].presence || l["subcategory_code"] }.compact.uniq

        raise Finanzas::Errors::InvalidBudgetLine, "lines must contain subcategory_code" if codes.empty?

        # Single query: fetch all subcategories + their category in one shot (no N+1)
        subcats = ::Subcategory
          .joins(:category)
          .where(code: codes)
          .select("subcategories.id, subcategories.code, subcategories.category_id, categories.name AS category_name")

        code_to_subcat = subcats.index_by(&:code)

        missing = codes - code_to_subcat.keys
        if missing.any?
          raise Finanzas::Errors::InvalidBudgetLine,
                "Unknown subcategory_code(s): #{missing.join(', ')}"
        end

        # One budget line per subcategory — upsert key is (account_id, subcategory_id, month, year)
        raw_lines.map do |line|
          code   = (line[:subcategory_code] || line["subcategory_code"]).to_s
          amount = (line[:amount] || line["amount"]).to_i
          subcat = code_to_subcat[code]
          {
            category_id:    subcat.category_id,
            subcategory_id: subcat.id,
            amount_limit:   amount
          }
        end
      end

      # Builds the enriched response for GET /monthly_plans/current.
      # Groups subcategory-level budgets by category and computes spend + projection per subcategory.
      def build_current_plan_response(plan)
        month = plan[:month]
        year  = plan[:year]

        # Fetch budgets for the month — includes category + subcategory (no N+1)
        budgets = ::Budget
          .where(account_id: current_account.id, month: month, year: year)
          .includes(:category, :subcategory)

        # Fetch spend totals per (category, subcategory, status) in one query
        spend_rows = ::Transaction
          .where(account_id: current_account.id, month: month, year: year, transaction_type: "expense")
          .where.not(category_id: nil)
          .select("category_id, subcategory_id, status, SUM(amount) AS total")
          .group(:category_id, :subcategory_id, :status)

        # { [category_id, subcategory_id] => { confirmed: N, pending: N } }
        spend_by_sub = Hash.new { |h, k| h[k] = { confirmed: 0, pending: 0 } }
        # { category_id => { confirmed: N, pending: N } }
        spend_by_cat = Hash.new { |h, k| h[k] = { confirmed: 0, pending: 0 } }

        spend_rows.each do |row|
          spend_by_sub[[row.category_id, row.subcategory_id]][row.status.to_sym] += row.total.to_i
          spend_by_cat[row.category_id][row.status.to_sym] += row.total.to_i
        end

        # Day-of-month projection: scale confirmed spend to full month
        today      = Date.today
        days_in    = Date.new(year, month, -1).day
        elapsed    = (today.month == month && today.year == year) ? today.day : days_in
        projection_scale = elapsed > 0 ? days_in.to_f / elapsed : 1.0

        # Group budgets by category
        by_category = budgets.group_by(&:category_id)

        category_rows = by_category.map do |cat_id, cat_budgets|
          cat = cat_budgets.first.category
          cat_spend = spend_by_cat[cat_id]
          cat_confirmed = cat_spend[:confirmed]
          cat_total     = cat_confirmed + cat_spend[:pending]
          cat_projected = (cat_confirmed * projection_scale).round
          cat_budgeted  = cat_budgets.sum(&:amount_limit)

          subcategory_rows = cat_budgets.map do |b|
            sub   = b.subcategory
            sub_spend = spend_by_sub[[cat_id, b.subcategory_id]]
            sub_confirmed = sub_spend[:confirmed]
            sub_total     = sub_confirmed + sub_spend[:pending]
            sub_projected = (sub_confirmed * projection_scale).round
            sub_signal    = build_budget_signal(category: cat, subcategory: sub, budgeted: b.amount_limit, spent: sub_total)

            {
              id:        b.subcategory_id,
              code:      sub&.code,
              name:      sub&.name,
              icon:      sub&.icon,
              budgeted:  b.amount_limit,
              spent:     sub_total,
              projected: sub_projected,
              signal_kind:   sub_signal[:kind],
              signal_label:  sub_signal[:label],
              signal_detail: sub_signal[:detail]
            }
          end

          category_signal = build_category_signal(
            category: cat,
            budgeted: cat_budgeted,
            spent: cat_total,
            subcategories: subcategory_rows
          )

          {
            code:          cat&.code,
            name:          cat&.name,
            color:         cat&.color,
            icon:          cat&.icon,
            budgeted:      cat_budgeted,
            spent:         cat_total,
            projected:     cat_projected,
            signal_kind:   category_signal[:kind],
            signal_label:  category_signal[:label],
            signal_detail: category_signal[:detail],
            subcategories: subcategory_rows
          }
        end

        plan.merge(
          month_label: "#{year}-#{month.to_s.rjust(2, '0')}",
          total_income: (plan[:base_budget_income].to_i + plan[:expected_variable_income].to_i),
          categories: category_rows
        )
      end

      def build_category_signal(category:, budgeted:, spent:, subcategories:)
        positive_count = subcategories.count { |row| row[:signal_kind] == "positive" }
        attention_count = subcategories.count { |row| row[:signal_kind] == "attention" }
        ratio = budgeted.to_i > 0 ? spent.to_f / budgeted.to_i : 0
        over_budget = budgeted.to_i > 0 && spent.to_i > budgeted.to_i

        if spent.to_i <= 0
          signal("neutral", "Sin movimiento", "Todavía no hay gasto real en esta parte del plan.")
        elsif attention_count.positive?
          signal(
            "attention",
            "Requiere atención",
            positive_count.positive? ?
              "Hay líneas que presionan el plan y otras que mejoran tu posición. Conviene revisar el detalle." :
              "Hay líneas dentro de esta categoría que sí están presionando el margen del mes."
          )
        elsif over_budget && positive_count.positive?
          signal("positive", "Sobre el plan, con mejora útil", "Parte del exceso parece mejorar deuda o construcción, no solo consumo.")
        elsif over_budget && discretionary_category?(category)
          signal("attention", "Sobre el plan", "Este exceso sí parece presionar el margen disponible del mes.")
        elsif over_budget && investment_category?(category)
          signal("neutral", "Sobre el plan, revisar liquidez", "Invertir más puede ser bueno, pero conviene revisar cómo afecta tu caja.")
        elsif over_budget
          signal("neutral", "Sobre el plan", "Se salió del plan, pero necesita contexto antes de juzgarse como un error.")
        elsif positive_count.positive?
          signal("positive", "Buen avance", "Hay movimientos en esta categoría que fortalecen tu posición financiera.")
        elsif ratio >= 0.85 && discretionary_category?(category)
          signal("attention", "Cerca del límite", "Queda poco margen en esta categoría y conviene mirarla de cerca.")
        elsif ratio >= 0.85
          signal("neutral", "Cerca del límite", "Todavía va dentro del plan, pero ya queda poco margen.")
        else
          signal("neutral", "En ritmo", "Esta categoría va dentro del plan del mes.")
        end
      end

      def build_budget_signal(category:, subcategory:, budgeted:, spent:)
        ratio = budgeted.to_i > 0 ? spent.to_f / budgeted.to_i : 0
        over_budget = budgeted.to_i > 0 && spent.to_i > budgeted.to_i

        if spent.to_i <= 0
          signal("neutral", "Sin movimiento", "Todavía no hay gasto real en esta línea.")
        elsif over_budget && debt_like_subcategory?(subcategory)
          signal("positive", "Sobre el plan, pero reduce deuda", "Este gasto parece un abono extra a deuda. Se salió del plan, pero puede mejorar tu pasivo.")
        elsif over_budget && investment_category?(category)
          signal("neutral", "Sobre el plan, revisar liquidez", "Invertir más puede ser bueno, pero conviene revisar cómo afecta tu caja del mes.")
        elsif over_budget && discretionary_category?(category)
          signal("attention", "Sobre el plan", "Este exceso sí presiona tu margen disponible del mes.")
        elsif over_budget
          signal("neutral", "Sobre el plan", "Esta línea se salió del plan y necesita contexto antes de juzgarla.")
        elsif ratio >= 0.85 && discretionary_category?(category)
          signal("attention", "Cerca del límite", "Queda poco margen en esta línea y conviene mirarla de cerca.")
        elsif debt_like_subcategory?(subcategory)
          signal("positive", "Pago en ritmo", "Esta línea sostiene o mejora tu salida de deuda dentro del plan.")
        elsif investment_category?(category) && spent.to_i.positive?
          signal("positive", "Construcción en ritmo", "Esta línea está aportando dentro del plan y suma a tu construcción.")
        elsif ratio >= 0.85
          signal("neutral", "Cerca del límite", "Todavía va dentro del plan, pero ya queda poco margen.")
        else
          signal("neutral", "En ritmo", "Esta línea va dentro del plan del mes.")
        end
      end

      def signal(kind, label, detail)
        { kind: kind, label: label, detail: detail }
      end

      def debt_like_subcategory?(subcategory)
        text = [subcategory&.code, subcategory&.name].compact.join(" ").downcase
        text.match?(/credit|crédito|credito|deuda|pr[eé]stamo|prestamo|loan|tarjeta/)
      end

      def investment_category?(category)
        category&.category_type == "investment" || category&.code == "investment"
      end

      def discretionary_category?(category)
        category&.category_type == "discretionary" ||
          %w[discretionary social dining_out personal_care].include?(category&.code)
      end
    end
  end
end
