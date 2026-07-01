module Finanzas
  module Interactors
    # Ensambla todo lo que el wizard de presupuesto necesita en una sola llamada.
    #
    # Metodología (ZBB estilo YNAB — ver specs/finanzas/presupuesto.md §2 y §6.2):
    # el wizard es un ENSAMBLADOR de fuentes de verdad, no un oráculo que inventa montos.
    #
    # Orden de asignación por par (tier, función) — RFC-0001 desacople:
    #   1. Recurrente (recurring_obligations)        → bloqueado, high
    #   2. Presupuesto confirmado de este mes        → confirmed
    #   3. Gasto planeado obligatorio                → high
    #   4. Baseline real (historial últimos 3 meses) → medium  ← manda sobre rollover
    #   5. Rollover explícito (plan mes anterior)    → medium
    #   6. Sin fuente                                → $0 (NO benchmark, NO reparto)
    #
    # El ahorro/objetivo se compromete ARRIBA (reduce el pozo), no como residuo.
    # Flexible es el residual: si la propuesta excede el pozo se muestra el sobregiro
    # (NDCF < 0), nunca se escala en silencio.
    class WizardData
      HISTORY_MONTHS = 3
      PLANNED_EXPENSE_TYPES = %w[mandatory_one_off irregular_maintenance].freeze
      # Un mes cuyo ingreso confirmado supera el recurrente por este factor se trata
      # como "windfall" (prima/aguinaldo): su gasto NO alimenta el baseline recurrente
      # y su excedente se reporta como ingreso extraordinario a asignar aparte (YNAB).
      WINDFALL_INCOME_RATIO = 1.2

      def initialize(
        income_repo:   Finanzas::Repositories::IncomeSourceRepository.new,
        category_repo: Finanzas::Repositories::CategoryRepository.new,
        ctx_repo:      Finanzas::Repositories::FinancialContextRepository.new,
        plan_repo:     Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      )
        @income_repo   = income_repo
        @category_repo = category_repo
        @ctx_repo      = ctx_repo
        @plan_repo     = plan_repo
      end

      def call(account_id:, user_id:, month: Date.current.month, year: Date.current.year)
        income_sources  = @income_repo.active_for_account(account_id)
        suggested_total = income_sources.sum { |s| s[:expected_amount].to_i }

        all_categories  = @category_repo.all_for_account(account_id)

        # Señales atribuidas por par (category_id, subcategory_id) — respeta el m2m:
        # una función en dos tiers no se cuenta doble.
        # Meses windfall (prima) — su gasto no debe fijar el baseline recurrente.
        windfall_months = detect_windfall_months(account_id, suggested_total)

        recurring_by_category = fetch_recurring_by_category(account_id)
        recurring_by_pair     = fetch_recurring_by_pair(account_id)
        planned_by_pair       = fetch_planned_by_pair(account_id)
        baseline_by_pair      = fetch_median_by_pair(account_id, windfall_months)
        confirmed_by_pair     = fetch_confirmed_budget_by_pair(account_id, month, year)
        prev_budget_by_pair   = fetch_prev_month_budget_by_pair(account_id, month, year)
        paid_by_pair          = fetch_paid_this_month_by_pair(account_id, month, year)

        fin_ctx = @ctx_repo.find_by_account(account_id) || {}
        phase   = Finanzas::Interactors::DerivePhase.new.call(account_id: account_id)

        # Reserva de ahorro — UNA sola fuente de verdad, por prioridad:
        # (1) override manual, (2) obligaciones materializadas de SavingsGoal, (3) derivada.
        savings_goal_total = fetch_savings_goal_obligations_total(account_id)
        goal_contribution  = if fin_ctx[:monthly_goal_contribution].to_i > 0
          fin_ctx[:monthly_goal_contribution].to_i
        elsif savings_goal_total > 0
          savings_goal_total
        else
          derive_goal_contribution(account_id, phase, suggested_total, recurring_by_category)
        end
        goal_contribution_configured = fin_ctx[:monthly_goal_contribution].to_i > 0

        # Pozo disponible para gasto = ingreso − ahorro comprometido (arriba, no residuo).
        available_pool = [ suggested_total - goal_contribution, 0 ].max

        income_section = build_income_section(income_sources, suggested_total)

        category_rows = build_category_rows(
          all_categories,
          recurring_by_category,
          recurring_by_pair,
          planned_by_pair,
          baseline_by_pair,
          confirmed_by_pair,
          prev_budget_by_pair,
          paid_by_pair
        )

        allocation = compute_allocation_meta(category_rows, available_pool, goal_contribution, suggested_total)
        allocation = allocation.merge(
          excluded_windfall_months: windfall_months.map { |(y, m)| format("%04d-%02d", y, m) }.sort
        )

        {
          income:                  income_section,
          categories:              category_rows,
          suggested_sinking_funds: build_suggested_sinking_funds(account_id),
          extraordinary_income:    summarize_extraordinary_income(account_id, suggested_total, windfall_months),
          goal_contribution: {
            amount:     goal_contribution,
            label:      goal_contribution_label(phase),
            phase:      phase,
            configured: goal_contribution_configured
          },
          phase:                   phase,
          carryover_from_previous: fetch_carryover_from_previous_plan(account_id, month, year),
          meta:                    allocation
        }
      end

      private

      # ── Income ───────────────────────────────────────────────────────────────

      def build_income_section(sources, suggested_total)
        {
          sources: sources.map { |s|
            {
              name:           s[:name],
              monthly_amount: s[:expected_amount].to_i,
              is_variable:    s[:is_variable] == true || %w[variable seasonal].include?(s[:classification].to_s)
            }
          },
          suggested_total: suggested_total,
          source_of_truth: "income_sources",
          can_edit_in_wizard: false,
          needs_setup: sources.empty?,
          edit_hint: "Edita ingresos en la sección de ingresos, no dentro del wizard."
        }
      end

      # ── Categories & subcategories ────────────────────────────────────────

      def build_category_rows(
        categories,
        recurring_by_category,
        recurring_by_pair,
        planned_by_pair,
        baseline_by_pair,
        confirmed_by_pair,
        prev_budget_by_pair,
        paid_by_pair
      )
        rows = []

        categories.each do |cat|
          next if cat.category_type == "income"
          # RFC-0001: investment/social ya no son tiers de gasto.
          next if %w[investment social].include?(cat.category_type)
          next if cat.code == "unknown" && cat.subcategories.none? { |s| !s.system? }

          sub_rows = build_subcategory_rows(
            cat,
            recurring_by_pair,
            planned_by_pair,
            baseline_by_pair,
            confirmed_by_pair,
            prev_budget_by_pair,
            paid_by_pair
          )

          # Recurrente atribuido a este tier pero no reclamado por ninguna de sus
          # subcategorías. Con la validación de coherencia debería ser 0; si existe,
          # se expone honestamente (NO se reparte a ciegas entre subcategorías vacías).
          covered = sub_rows.sum { |s| s[:locked] ? s[:suggested_amount] : 0 }
          orphan  = [ recurring_by_category[cat.id].to_i - covered, 0 ].max

          rows << {
            code:                 cat.code,
            name:                 cat.name,
            color:                cat.color,
            icon:                 cat.icon,
            subcategories:        sub_rows,
            suggested_total:      sub_rows.sum { |s| s[:suggested_amount] } + orphan,
            unassigned_recurring: orphan
          }
        end

        rows
      end

      def build_subcategory_rows(
        category,
        recurring_by_pair,
        planned_by_pair,
        baseline_by_pair,
        confirmed_by_pair,
        prev_budget_by_pair,
        paid_by_pair
      )
        category.subcategories.map do |sub|
          key       = [ category.id, sub.id ]
          recurring = recurring_by_pair[key].to_i
          confirmed = confirmed_by_pair[key]
          planned   = planned_by_pair[key].to_i

          if recurring > 0
            paid   = paid_by_pair[key].to_i
            status = paid >= recurring ? "covered" : "pending"
            build_subcategory_row(
              sub,
              suggested_amount: recurring,
              confidence: "high",
              source: "recurring",
              locked: true,
              source_of_truth: "recurring_obligations",
              edit_hint: "Se edita desde gastos recurrentes.",
              extra: { funding_status: status, paid_this_month: paid }
            )
          elsif confirmed
            build_subcategory_row(
              sub,
              suggested_amount: confirmed,
              confidence: "confirmed",
              source: "confirmed_budget",
              locked: false,
              source_of_truth: "budgets",
              edit_hint: "Monto del plan confirmado para este mes."
            )
          elsif planned > 0
            build_subcategory_row(
              sub,
              suggested_amount: planned,
              confidence: "high",
              source: "planned_expense",
              locked: false,
              source_of_truth: "planned_expenses",
              edit_hint: "Se calcula desde gastos planeados obligatorios."
            )
          elsif baseline_by_pair.key?(key)
            build_subcategory_row(
              sub,
              suggested_amount: baseline_by_pair[key],
              confidence: "medium",
              source: "history",
              locked: false,
              source_of_truth: "transactions",
              edit_hint: "Mediana de tu gasto en los últimos #{HISTORY_MONTHS} meses (robusta a meses atípicos)."
            )
          elsif prev_budget_by_pair.key?(key)
            build_subcategory_row(
              sub,
              suggested_amount: prev_budget_by_pair[key],
              confidence: "medium",
              source: "prev_plan",
              locked: false,
              source_of_truth: "budgets",
              edit_hint: "Monto del plan del mes anterior (sin historial nuevo). Ajusta si cambió."
            )
          else
            build_subcategory_row(
              sub,
              suggested_amount: 0,
              confidence: "low",
              source: "none",
              locked: false,
              source_of_truth: "none",
              edit_hint: "Sin historial ni fuente fija; define un monto si aplica."
            )
          end
        end
      end

      def build_subcategory_row(subcategory, suggested_amount:, confidence:, source:, locked:, source_of_truth:, edit_hint:, extra: {})
        {
          code:             subcategory.code,
          name:             subcategory.name,
          icon:             subcategory.icon,
          suggested_amount: suggested_amount,
          confidence:       confidence,
          source:           source,
          locked:           locked,
          source_of_truth:  source_of_truth,
          edit_hint:        edit_hint
        }.merge(extra)
      end

      # ── Allocation meta (ZBB) ─────────────────────────────────────────────────
      #
      # No muta montos. Reporta el estado del presupuesto base-cero: qué está
      # comprometido, qué es flexible, y cuánto queda por asignar (puede ser
      # negativo = sobregiro, NC-7). El humano/agente reconcilia a cero.
      def compute_allocation_meta(rows, available_pool, goal_contribution, income_total)
        all_subs      = rows.flat_map { |c| c[:subcategories] }
        locked_total  = all_subs.sum { |s| s[:locked] ? s[:suggested_amount] : 0 }
        orphan_total  = rows.sum { |c| c[:unassigned_recurring].to_i }
        committed     = locked_total + orphan_total
        flexible      = all_subs.sum { |s| s[:locked] ? 0 : s[:suggested_amount] }
        assigned      = committed + flexible
        por_asignar   = available_pool - assigned

        {
          income_total:      income_total,
          goal_contribution: goal_contribution,
          available_pool:    available_pool,
          committed_total:   committed,
          flexible_total:    flexible,
          assigned_total:    assigned,
          unassigned:        orphan_total,
          por_asignar:       por_asignar,
          overassigned:      por_asignar < 0
        }
      end

      # ── Goal contribution derivation ──────────────────────────────────────

      def goal_contribution_label(phase)
        case phase.to_s
        when "debt_payoff"    then "Reservado para pago extra de deuda"
        when "emergency_fund" then "Reservado para fondo de emergencia"
        else "Aporte a objetivo financiero"
        end
      end

      # Cuando el usuario no fijó monthly_goal_contribution, se deriva de la fase
      # y los datos reales — el plan siempre reserva ahorro primero (NC-3, NC-5).
      def derive_goal_contribution(account_id, phase, income, recurring_by_category)
        return 0 unless %w[emergency_fund debt_payoff].include?(phase.to_s)

        case phase.to_s
        when "emergency_fund"
          derive_ef_contribution(account_id, recurring_by_category)
        when "debt_payoff"
          derive_debt_contribution(account_id, income)
        end.to_i
      end

      def derive_ef_contribution(account_id, recurring_by_category)
        ef_goal = ::SavingsGoal
          .where(account_id: account_id)
          .find { |g| g.name.match?(/emergencia|emergency/i) }

        if ef_goal&.monthly_contribution_needed.to_i > 0
          return round_to_thousands(ef_goal.monthly_contribution_needed)
        end

        committed_monthly = recurring_by_category.values.sum.to_i
        return 0 if committed_monthly <= 0

        current_ef = ef_goal&.current_amount.to_i
        gap = [ committed_monthly - current_ef, 0 ].max
        return 0 if gap <= 0

        round_to_thousands((gap.to_f / 12).ceil)
      end

      def derive_debt_contribution(account_id, income)
        focal_debt = ::Debt
          .where(account_id: account_id, status: :active)
          .order(:current_balance)
          .first

        return 0 unless focal_debt

        monthly = (focal_debt.current_balance.to_f / 12).ceil
        monthly = [ monthly, 100_000 ].max
        monthly = [ monthly, (income * 0.20).to_i ].min
        round_to_thousands(monthly)
      end

      def round_to_thousands(amount)
        ((amount.to_f / 1000).round * 1000).to_i
      end

      # ── Goal obligations & carryover ─────────────────────────────────────────

      def fetch_savings_goal_obligations_total(account_id)
        ::RecurringObligation.active
          .where(account_id: account_id, source_type: "SavingsGoal")
          .sum(:amount)
          .to_i
      end

      def fetch_carryover_from_previous_plan(account_id, month, year)
        last = @plan_repo.last_closed(account_id: account_id, limit: 1).first
        return 0 unless last

        prev = Date.new(year, month, 1).prev_month
        return 0 unless last[:month] == prev.month && last[:year] == prev.year

        last.dig(:execution_snapshot, "overflow_amount").to_i
      end

      # ── DB Queries (por par category_id + subcategory_id) ─────────────────────

      # { category_id => total_amount } — para detectar recurrente huérfano por tier.
      def fetch_recurring_by_category(account_id)
        ::RecurringObligation
          .where(account_id: account_id, active: true)
          .where.not(category_id: nil)
          .group(:category_id)
          .sum(:amount)
      end

      # { [category_id, subcategory_id] => total_amount }
      def fetch_recurring_by_pair(account_id)
        ::RecurringObligation
          .where(account_id: account_id, active: true)
          .where.not(category_id: nil).where.not(subcategory_id: nil)
          .group(:category_id, :subcategory_id)
          .sum(:amount)
      end

      # { [category_id, subcategory_id] => suggested_monthly_contribution }
      def fetch_planned_by_pair(account_id)
        planned = ::PlannedExpense
          .where(account_id: account_id, status: "planned", planning_type: PLANNED_EXPENSE_TYPES)
          .where("target_date >= ?", Date.current.beginning_of_month)
          .where.not(category_id: nil).where.not(subcategory_id: nil)

        planned.each_with_object(Hash.new(0)) do |expense, hash|
          hash[[ expense.category_id, expense.subcategory_id ]] += monthly_planned_contribution(expense)
        end
      end

      # { [category_id, subcategory_id] => mediana_mensual } — últimos HISTORY_MONTHS.
      # Mediana (no media) de los totales mensuales: un mes atípico no infla el baseline.
      # Se calcula sobre los meses CON actividad ("cuando gastas en esto, cuánto sueles gastar").
      # Excluye meses windfall: su gasto está financiado por ingreso extraordinario, no
      # representa tu presupuesto recurrente.
      def fetch_median_by_pair(account_id, windfall_months = Set.new)
        since = HISTORY_MONTHS.months.ago.beginning_of_month.to_date

        monthly = ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed")
          .where("date >= ?", since)
          .where.not(category_id: nil).where.not(subcategory_id: nil)
          .group(:category_id, :subcategory_id, :year, :month)
          .sum(:amount)

        buckets = Hash.new { |h, k| h[k] = [] }
        monthly.each do |(cat_id, sub_id, y, m), total|
          next if windfall_months.include?([ y, m ])

          buckets[[ cat_id, sub_id ]] << total.to_i
        end
        buckets.transform_values { |monthly_totals| median(monthly_totals) }
      end

      # Meses (dentro de la ventana de historial) cuyo ingreso confirmado supera al
      # recurrente esperado por WINDFALL_INCOME_RATIO. Set de [year, month].
      def detect_windfall_months(account_id, expected_recurring_income)
        return Set.new if expected_recurring_income.to_i <= 0

        since   = HISTORY_MONTHS.months.ago.beginning_of_month.to_date
        ceiling = expected_recurring_income * WINDFALL_INCOME_RATIO

        ::Transaction
          .where(account_id: account_id, transaction_type: "income", status: "confirmed")
          .where("date >= ?", since)
          .group(:year, :month)
          .sum(:amount)
          .select { |_ym, total| total.to_i > ceiling }
          .keys
          .to_set
      end

      # Ingreso extraordinario detectado en la ventana: el excedente sobre lo recurrente
      # en meses windfall. Se reporta para asignarlo aparte (metas/deuda/bolsillos),
      # no para inflar el presupuesto mensual (YNAB — el dinero de una vez tiene su propio job).
      def summarize_extraordinary_income(account_id, expected_recurring_income, windfall_months)
        return { detected_recent: 0, months: [], hint: nil } if windfall_months.empty?

        since = HISTORY_MONTHS.months.ago.beginning_of_month.to_date
        by_month = ::Transaction
          .where(account_id: account_id, transaction_type: "income", status: "confirmed")
          .where("date >= ?", since)
          .group(:year, :month)
          .sum(:amount)

        detail = windfall_months.map do |(y, m)|
          surplus = [ by_month[[ y, m ]].to_i - expected_recurring_income, 0 ].max
          { month: format("%04d-%02d", y, m), surplus: surplus }
        end.sort_by { |h| h[:month] }

        {
          detected_recent: detail.sum { |h| h[:surplus] },
          months:          detail,
          hint:            "Ingreso extraordinario (prima/aguinaldo). Asígnalo aparte a metas, deuda o bolsillos; no lo sumes al presupuesto recurrente."
        }
      end

      def median(values)
        return 0 if values.empty?

        sorted = values.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
      end

      # { [category_id, subcategory_id] => amount_limit } — presupuesto confirmado del mes.
      def fetch_confirmed_budget_by_pair(account_id, month, year)
        ::Budget
          .where(account_id: account_id, month: month, year: year)
          .where.not(category_id: nil).where.not(subcategory_id: nil)
          .pluck(:category_id, :subcategory_id, :amount_limit)
          .each_with_object({}) { |(cid, sid, amt), h| h[[ cid, sid ]] = amt }
      end

      # { [category_id, subcategory_id] => amount_limit } — plan del mes anterior.
      def fetch_prev_month_budget_by_pair(account_id, month, year)
        prev = Date.new(year, month, 1).prev_month
        ::Budget
          .where(account_id: account_id, month: prev.month, year: prev.year)
          .where.not(category_id: nil).where.not(subcategory_id: nil)
          .pluck(:category_id, :subcategory_id, :amount_limit)
          .each_with_object({}) { |(cid, sid, amt), h| h[[ cid, sid ]] = amt }
      end

      # { [category_id, subcategory_id] => total_confirmed_spend } — gasto real del mes.
      def fetch_paid_this_month_by_pair(account_id, month, year)
        ::Transaction
          .where(
            account_id:       account_id,
            transaction_type: "expense",
            status:           "confirmed",
            month:            month,
            year:             year
          )
          .where.not(category_id: nil).where.not(subcategory_id: nil)
          .group(:category_id, :subcategory_id)
          .sum(:amount)
          .transform_values(&:to_i)
      end

      def monthly_planned_contribution(expense)
        months = months_until_target(expense.target_date)
        (expense.amount_estimated.to_f / months).ceil
      end

      def months_until_target(target_date)
        today = Date.current.beginning_of_month
        target = target_date.to_date.beginning_of_month
        delta = (target.year * 12 + target.month) - (today.year * 12 + today.month) + 1
        [ delta, 1 ].max
      end

      # Gastos planeados que necesitan bolsillo y aún no lo tienen.
      def build_suggested_sinking_funds(account_id)
        funded_expense_ids = ::SinkingFund
          .where(account_id: account_id, active: true)
          .where.not(planned_expense_id: nil)
          .pluck(:planned_expense_id)
          .to_set

        ::PlannedExpense
          .where(account_id: account_id, status: "planned", planning_type: PLANNED_EXPENSE_TYPES)
          .where("target_date >= ?", Date.current.beginning_of_month)
          .reject { |exp| funded_expense_ids.include?(exp.id) }
          .map do |exp|
            {
              planned_expense_id: exp.id,
              name:               exp.name,
              target_amount:      exp.amount_estimated,
              target_date:        exp.target_date&.iso8601,
              suggested_monthly:  monthly_planned_contribution(exp),
              months_remaining:   months_until_target(exp.target_date),
              planning_type:      exp.planning_type
            }
          end
      end
    end
  end
end
