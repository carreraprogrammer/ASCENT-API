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

        materialize_goal_contribution(plan[:month], plan[:year])
        apply_goal_contribution_amount if params[:goal_contribution_amount].present?

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

      def destroy
        return unless require_scope!("budgets:update")
        plan = ::MonthlyFinancialPlan.find_by!(id: params[:id], account: current_account)
        ActiveRecord::Base.transaction do
          # Sin esto, los budgets del mes quedan huérfanos y burn_rate sigue
          # rindiendo "gavetas fantasma" en dashboard y detalle.
          ::Budget.where(account_id: current_account.id, month: plan.month, year: plan.year).delete_all
          plan.destroy!
        end
        render json: { data: { id: params[:id] } }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [ { status: "404", detail: "Plan no encontrado" } ] }, status: :not_found
      end

      private

      # Applies the user-specified monthly contribution amount to the first active
      # SavingsGoal obligation for the account. Uses update_column to bypass callbacks
      # so we don't trigger a full recalculation loop.
      def apply_goal_contribution_amount
        desired = params[:goal_contribution_amount].to_i
        return if desired <= 0

        obligation = ::RecurringObligation
          .where(account_id: current_account.id, active: true, source_type: "SavingsGoal")
          .first
        return unless obligation
        return if obligation.amount == desired

        obligation.update_column(:amount, desired)
        obligation.source&.update_column(:monthly_contribution_needed, desired)
      rescue => e
        Rails.logger.warn "[monthly_plans#confirm] apply_goal_contribution_amount failed: #{e.message}"
      end

      # On every plan confirmation, creates a SavingsGoal for the emergency fund if the
      # account is in the emergency_fund phase and no EF goal exists yet.
      # The goal's after_commit hook creates the linked RecurringObligation so the
      # contribution appears in the dashboard obligations list.
      def materialize_goal_contribution(month, year)
        phase = Finanzas::Interactors::DerivePhase.new.call(account_id: current_account.id)
        return unless phase == "emergency_fund"

        return if ::SavingsGoal
          .where(account_id: current_account.id)
          .any? { |g| g.name.match?(/emergencia|emergency|fondo/i) }

        committed_monthly = ::RecurringObligation
          .where(account_id: current_account.id, active: true)
          .sum(:amount).to_i

        return if committed_monthly <= 0

        raw_monthly          = (committed_monthly / 12.0).ceil
        monthly_contribution = [ (raw_monthly / 1000.0).round * 1000, 1000 ].max
        target_amount        = monthly_contribution * 12
        target_date          = Date.new(year.to_i, month.to_i, 1) >> 12

        ::SavingsGoal.create!(
          user_id:        current_owner_user_id,
          account_id:     current_account.id,
          name:           "Fondo de Emergencia",
          target_amount:  target_amount,
          current_amount: 0,
          target_date:    target_date,
          status:         "active"
        )
      rescue => e
        Rails.logger.warn "[monthly_plans#confirm] materialize_goal_contribution failed: #{e.message}"
      end

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

        # Fetch spend totals per (category, subcategory, status) — respects covers_period_month/year
        # so transactions paid in a prior month that cover this period are counted correctly.
        spend_rows = ::Transaction
          .where(account_id: current_account.id, transaction_type: "expense")
          .where.not(category_id: nil)
          .where(
            "(covers_period_month IS NOT NULL AND covers_period_year IS NOT NULL" \
            "  AND covers_period_month = :m AND covers_period_year = :y)" \
            " OR (covers_period_month IS NULL AND month = :m AND year = :y)",
            m: month, y: year
          )
          .select("category_id, subcategory_id, status, SUM(amount) AS total")
          .group(:category_id, :subcategory_id, :status)

        # { [category_id, subcategory_id] => { confirmed: N, pending: N } }
        spend_by_sub = Hash.new { |h, k| h[k] = { confirmed: 0, pending: 0 } }
        # { category_id => { confirmed: N, pending: N } }
        spend_by_cat = Hash.new { |h, k| h[k] = { confirmed: 0, pending: 0 } }

        spend_rows.each do |row|
          spend_by_sub[[ row.category_id, row.subcategory_id ]][row.status.to_sym] += row.total.to_i
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
          cat_budgeted  = cat_budgets.sum { |b| b.amount_limit.to_i }
          cat_behavior  = financial_behavior_for(category: cat)

          subcategory_rows = cat_budgets
            .reject { |b| b.amount_limit.to_i == 0 }
            .map do |b|
              sub   = b.subcategory
              sub_spend = spend_by_sub[[ cat_id, b.subcategory_id ]]
              sub_confirmed = sub_spend[:confirmed]
              sub_total     = sub_confirmed + sub_spend[:pending]
              sub_projected = (sub_confirmed * projection_scale).round
              sub_behavior  = financial_behavior_for(category: cat, subcategory: sub)
              sub_signal    = build_budget_signal(category: cat, subcategory: sub, budgeted: b.amount_limit, spent: sub_total)

              {
                id:        b.subcategory_id,
                code:      sub&.code,
                name:      sub&.name,
                icon:      sub&.icon,
                budgeted:  b.amount_limit,
                spent:     sub_total,
                projected: sub_projected,
                behavior:  sub_behavior,
                primary_metric: budget_primary_metric(
                  behavior: sub_behavior,
                  name: sub&.name || sub&.code || "Esta línea",
                  budgeted: b.amount_limit,
                  spent: sub_total,
                  projected: sub_projected,
                  elapsed: elapsed,
                  days_in: days_in
                ),
                signal_kind:   sub_signal[:kind],
                signal_label:  sub_signal[:label],
                signal_detail: sub_signal[:detail]
              }
            end

          next if subcategory_rows.empty? && cat_budgeted == 0

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
            behavior:      cat_behavior,
            primary_metric: budget_primary_metric(
              behavior: cat_behavior,
              name: cat&.name || cat&.code || "Esta categoría",
              budgeted: cat_budgeted,
              spent: cat_total,
              projected: cat_projected,
              elapsed: elapsed,
              days_in: days_in
            ),
            signal_kind:   category_signal[:kind],
            signal_label:  category_signal[:label],
            signal_detail: category_signal[:detail],
            subcategories: subcategory_rows
          }
        end

        # Append savings goal obligations as synthetic rows so they appear in the
        # plan detail even though they have no subcategory_id / Budget record.
        savings_rows = build_savings_goal_rows(elapsed, days_in)
        category_rows += savings_rows

        plan.merge(
          month_label: "#{year}-#{month.to_s.rjust(2, '0')}",
          total_income: (plan[:base_budget_income].to_i + plan[:expected_variable_income].to_i),
          categories: category_rows
        )
      end

      # Returns one synthetic category row per active SavingsGoal RecurringObligation.
      # These obligations are tracked outside the Budget table so they'd otherwise
      # be invisible in the plan detail view.
      def build_savings_goal_rows(elapsed, days_in)
        obligations = ::RecurringObligation
          .where(account_id: current_account.id, active: true, source_type: "SavingsGoal")
          .includes(:source)

        return [] if obligations.empty?

        obligations.map do |ob|
          goal   = ob.source
          amount = ob.amount.to_i
          name   = goal&.name || ob.name

          sub_row = {
            id:        nil,
            code:      "savings_goal_#{ob.source_id}",
            name:      ob.name,
            icon:      "trophy",
            budgeted:  amount,
            spent:     0,
            projected: 0,
            behavior:  "savings_goal",
            primary_metric: budget_primary_metric(
              behavior: "savings_goal",
              name:     ob.name,
              budgeted: amount,
              spent:    0,
              projected: 0,
              elapsed:  elapsed,
              days_in:  days_in
            ),
            signal_kind:   "positive",
            signal_label:  "Comprometido",
            signal_detail: "Separado antes de distribuir el presupuesto."
          }

          {
            code:          "objetivos",
            name:          name,
            color:         "#1A9E4A",
            icon:          "trophy",
            budgeted:      amount,
            spent:         0,
            projected:     0,
            behavior:      "savings_goal",
            primary_metric: budget_primary_metric(
              behavior: "savings_goal",
              name:     name,
              budgeted: amount,
              spent:    0,
              projected: 0,
              elapsed:  elapsed,
              days_in:  days_in
            ),
            signal_kind:   "positive",
            signal_label:  "Comprometido",
            signal_detail: "Este aporte está reservado antes de distribuir el resto del presupuesto.",
            subcategories: [ sub_row ]
          }
        end
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

      def financial_behavior_for(category:, subcategory: nil)
        text = [
          category&.category_type,
          category&.code,
          category&.name,
          subcategory&.code,
          subcategory&.name
        ].compact.join(" ").downcase

        return "debt_payment" if text.match?(/debt|deuda|credit|cr[eé]dito|prestamo|pr[eé]stamo|loan|tarjeta/)
        return "savings_goal" if text.match?(/saving|savings|ahorro|inversi[oó]n|investment|fondo|emergencia/)
        return "fixed_once" if text.match?(/rent|arriendo|alquiler|seguro|insurance|predial|matr[ií]cula/)
        return "fixed_recurring" if text.match?(/subscription|suscrip|netflix|spotify|internet|celular|phone|gimnasio|gym|servicio|utility|utilities/)
        return "variable_spiky" if text.match?(/health|salud|ropa|regalo|gift|reparaci[oó]n|repair|imprevisto|travel|viaje/)
        return "variable_linear" if text.match?(/food|comida|groceries|mercado|transport|transporte|dining|domicilio|restaurant|cafe|caf[eé]|snack|salida/)

        case category&.category_type.to_s
        when "committed"
          "fixed_recurring"
        when "necessary", "discretionary", "social"
          "variable_linear"
        when "investment"
          "savings_goal"
        else
          "variable_spiky"
        end
      end

      def budget_primary_metric(behavior:, name:, budgeted:, spent:, projected:, elapsed:, days_in:)
        ratio = budgeted.to_i.positive? ? spent.to_f / budgeted.to_i : 0
        projected_over = projected.to_i - budgeted.to_i

        case behavior
        when "variable_linear"
          status = if budgeted.to_i.positive? && projected > budgeted
                     "critical"
          elsif budgeted.to_i.positive? && ratio >= month_progress_ratio(elapsed, days_in) + 0.2
                     "warning"
          else
                     "comfortable"
          end
          {
            kind: "month_end_projection",
            status: status,
            title: status == "critical" ? "Vas más rápido de lo planeado" : "Estimado a fin de mes",
            body: projected_over.positive? ?
              "A este ritmo cerrarías #{format_cop(projected_over)} por encima del presupuesto." :
              "A este ritmo cerrarías dentro del presupuesto.",
            value: projected,
            budget: budgeted
          }
        when "fixed_once", "fixed_recurring"
          pending = [ budgeted.to_i - spent.to_i, 0 ].max
          {
            kind: "payment_status",
            status: pending.positive? ? "warning" : "comfortable",
            title: pending.positive? ? "Pago pendiente" : "Pago cubierto",
            body: pending.positive? ?
              "Aún faltan #{format_cop(pending)} por cubrir en #{name}." :
              "#{name} ya está cubierto este mes.",
            value: pending,
            budget: budgeted
          }
        when "savings_goal"
          pct = budgeted.to_i.positive? ? ((spent.to_f / budgeted.to_i) * 100).round : 0
          {
            kind: "goal_progress",
            status: pct >= 100 ? "comfortable" : pct >= 60 ? "warning" : "critical",
            title: "Avance de meta",
            body: "Llevas #{pct}% de la meta mensual.",
            value: pct,
            budget: budgeted
          }
        when "debt_payment"
          pct = budgeted.to_i.positive? ? ((spent.to_f / budgeted.to_i) * 100).round : 0
          {
            kind: "debt_progress",
            status: spent.to_i.positive? ? "comfortable" : "warning",
            title: spent.to_i.positive? ? "Pago a deuda registrado" : "Pago pendiente",
            body: spent.to_i.positive? ?
              "Este pago ayuda a reducir deuda y sostiene tu plan." :
              "Todavía no hay pago registrado para esta deuda.",
            value: pct,
            budget: budgeted
          }
        else
          pct = budgeted.to_i.positive? ? ((spent.to_f / budgeted.to_i) * 100).round : 0
          status = pct >= 100 ? "critical" : pct >= 70 ? "warning" : "comfortable"
          {
            kind: "spiky_context",
            status: status,
            title: status == "comfortable" ? "Gasto puntual bajo control" : "Gasto puntual relevante",
            body: "Este gasto consumió #{pct}% del presupuesto asignado.",
            value: pct,
            budget: budgeted
          }
        end
      end

      def month_progress_ratio(elapsed, days_in)
        return 0 if days_in.to_i <= 0

        elapsed.to_f / days_in.to_i
      end

      def format_cop(amount)
        "$#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse}"
      end

      def debt_like_subcategory?(subcategory)
        text = [ subcategory&.code, subcategory&.name ].compact.join(" ").downcase
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
