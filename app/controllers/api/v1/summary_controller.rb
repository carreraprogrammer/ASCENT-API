module Api
  module V1
    class SummaryController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      COLOMBIA_OFFSET = -5 * 3600  # UTC-5

      # GET /api/v1/summary?month=&year=
      def show
        return unless require_scope!("summary:read")
        now_col = Time.now.utc + COLOMBIA_OFFSET
        month   = (params[:month] || now_col.month).to_i
        year    = (params[:year]  || now_col.year).to_i
        account_id = current_account.id

        balance              = txn_repo.balance(account_id: account_id, month: month, year: year)
        budgets              = budget_repo.for_month(account_id: account_id, month: month, year: year)
        debts                = debt_repo.all_for_account(account_id)
        ctx                  = ctx_repo.find_by_account(account_id)
        plan                 = plan_repo.find_for_month(account_id: account_id, month: month, year: year)
        income_sources       = income_source_repo.active_for_account(account_id)
        realized_income_by_source = income_realized_by_source(account_id, month, year)
        carryover_from_previous_month = previous_month_carryover(account_id, month, year)
        balance = balance.merge(
          carryover_from_previous_month: carryover_from_previous_month,
          net_balance: balance[:balance_confirmed] + carryover_from_previous_month
        )

        confirmed_balance    = balance[:income_confirmed].to_i - balance[:expense_confirmed].to_i +
                               carryover_from_previous_month.to_i
        period               = Date.new(year, month, 1)
        realized_obligations = realized_recurring_obligations_for_period(account_id, period)
        recurring_obs        = ::RecurringObligation.where(account_id: account_id, active: true)
                                 .map { |o| { id: o.id, name: o.name, amount: o.amount, due_day: o.due_day, active: o.active } }
        necessary_txns       = necessary_transactions_for_burn(account_id, now_col.to_date)

        cash_flow_runway     = Finanzas::Interactors::CashFlowRunway.new.call(
                                 confirmed_balance:      confirmed_balance,
                                 necessary_transactions: necessary_txns,
                                 income_sources:         income_sources,
                                 recurring_obligations:  recurring_obs,
                                 realized_obligations:   realized_obligations,
                                 today:                  now_col.to_date
                               )

        savings_goals = ::SavingsGoal
          .where(account_id: account_id, status: "active")
          .order(priority: :asc)
          .map { |g| { name: g.name, target_amount: g.target_amount,
                       current_amount: g.current_amount,
                       monthly_contribution_needed: g.monthly_contribution_needed,
                       target_date: g.target_date, status: g.status } }

        overflow = build_overflow_status(
                     plan, balance, ctx, debts,
                     income_sources, realized_income_by_source,
                     carryover_from_previous_month
                   )

        render json: {
          period:            { month: month, year: year },
          balance:           balance,
          month_execution:   build_month_execution(account_id, month, year, income_sources),
          burn_rate:         build_burn_rate(account_id, month, year, budgets, now_col),
          debts:             build_debts_summary(debts),
          monthly_plan:      build_monthly_plan_summary(plan),
          overflow_status:   overflow,
          financial_context: build_context_summary(ctx, plan, debts),
          cash_flow_runway:  cash_flow_runway,
          savings_goals:     savings_goals
        }
      end

      private

      # ── Month execution ──────────────────────────────────────────────────────

      def build_month_execution(account_id, month, year, income_sources)
        period = Date.new(year, month, 1)

        {
          income: build_income_execution(account_id, period, income_sources),
          recurring_obligations: build_recurring_obligation_execution(account_id, period)
        }
      end

      def build_income_execution(account_id, period, income_sources)
        sources = Array(income_sources)
        realized_by_source = realized_income_by_source_for_period(account_id, period)
        confirmed_income_total = ::Transaction
          .where(
            account_id: account_id,
            month: period.month,
            year: period.year,
            transaction_type: "income",
            status: "confirmed"
          )
          .sum(:amount)

        expected_total = sources.sum { |source| source[:expected_amount].to_i }
        source_rows = sources.map do |source|
          expected = source[:expected_amount].to_i
          realized = realized_by_source.fetch(source[:id], 0).to_i
          delivered = expected.positive? ? [ realized, expected ].min : realized
          remaining = [ expected - delivered, 0 ].max

          {
            id: source[:id],
            name: source[:name],
            classification: source[:classification],
            expected_amount: expected,
            delivered_amount: delivered,
            remaining_amount: remaining,
            pct: pct(delivered, expected),
            status: execution_status(delivered, expected),
            expected_day_from: source[:expected_day_from],
            expected_day_to: source[:expected_day_to]
          }
        end

        delivered_expected_total = source_rows.sum { |row| row[:delivered_amount] }
        unlinked_confirmed_total = [
          confirmed_income_total - realized_by_source.values.sum(&:to_i),
          0
        ].max

        {
          expected_total: expected_total,
          delivered_expected_total: delivered_expected_total,
          remaining_expected_total: [ expected_total - delivered_expected_total, 0 ].max,
          pct: pct(delivered_expected_total, expected_total),
          confirmed_income_total: confirmed_income_total,
          unlinked_confirmed_total: unlinked_confirmed_total,
          base: income_execution_bucket(source_rows, "base"),
          variable: income_execution_bucket(source_rows, "variable"),
          sources: source_rows
        }
      end

      def build_recurring_obligation_execution(account_id, period)
        obligations = ::RecurringObligation
          .includes(:category, :subcategory)
          .where(account_id: account_id, active: true)
          .order(:due_day, :created_at)
          .to_a
        covered_by_obligation = realized_recurring_obligations_for_period(account_id, period)

        rows = obligations.map do |obligation|
          expected = obligation.amount.to_i
          realized = covered_by_obligation.fetch(obligation.id, 0).to_i
          covered = expected.positive? ? [ realized, expected ].min : realized
          remaining = [ expected - covered, 0 ].max

          {
            id: obligation.id,
            name: obligation.name,
            expected_amount: expected,
            covered_amount: covered,
            remaining_amount: remaining,
            pct: pct(covered, expected),
            status: execution_status(covered, expected),
            due_day: obligation.due_day,
            category_id: obligation.category_id,
            category_code: obligation.category&.code,
            subcategory_id: obligation.subcategory_id,
            subcategory_code: obligation.subcategory&.code,
            source_type: obligation.source_type,
            source_id: obligation.source_id
          }
        end

        expected_total = rows.sum { |row| row[:expected_amount] }
        covered_total = rows.sum { |row| row[:covered_amount] }

        {
          expected_total: expected_total,
          covered_total: covered_total,
          remaining_total: [ expected_total - covered_total, 0 ].max,
          pct: pct(covered_total, expected_total),
          covered_count: rows.count { |row| row[:status] == "covered" },
          total_count: rows.size,
          items: rows
        }
      end

      def realized_income_by_source_for_period(account_id, period)
        linked = ::Transaction
          .where(
            account_id: account_id,
            transaction_type: "income",
            status: "confirmed"
          )
          .where.not(income_source_id: nil)
          .select { |transaction| transaction_applies_to_period?(transaction, period) }
          .each_with_object(Hash.new(0)) do |transaction, hash|
            hash[transaction.income_source_id] += transaction.amount.to_i
          end

        ::Transaction
          .where(
            account_id: account_id,
            transaction_type: "income",
            status: "confirmed",
            income_source_id: nil
          )
          .select { |transaction| transaction_applies_to_period?(transaction, period) }
          .each do |transaction|
            source_id = income_matcher.call(
              account_id: account_id,
              date: transaction.date,
              concept: transaction.concept,
              amount: transaction.amount
            )
            linked[source_id] += transaction.amount.to_i if source_id.present?
          end

        linked
      end

      def realized_recurring_obligations_for_period(account_id, period)
        linked = ::Transaction
          .where(
            account_id: account_id,
            transaction_type: "expense",
            status: "confirmed"
          )
          .where.not(recurring_obligation_id: nil)
          .select { |transaction| transaction_applies_to_period?(transaction, period) }
          .each_with_object(Hash.new(0)) do |transaction, hash|
            hash[transaction.recurring_obligation_id] += transaction.amount.to_i
          end

        ::Transaction
          .where(
            account_id: account_id,
            transaction_type: "expense",
            status: "confirmed",
            recurring_obligation_id: nil
          )
          .select { |transaction| transaction_applies_to_period?(transaction, period) }
          .each do |transaction|
            match = structure_detector.call(
              account_id: account_id,
              concept: transaction.concept,
              amount: transaction.amount,
              subcategory_id: transaction.subcategory_id,
              date_str: transaction.date
            )
            next unless %w[debt recurring].include?(match[:match_type])
            next unless match[:confidence] == "high"
            next if match[:match_id].blank?

            linked[match[:match_id]] += transaction.amount.to_i
          end

        linked
      end

      def transaction_applies_to_period?(transaction, period)
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

      def income_execution_bucket(rows, classification)
        filtered = rows.select do |row|
          classification == "variable" ? variable_income_row?(row) : row[:classification] == classification
        end
        expected = filtered.sum { |row| row[:expected_amount] }
        delivered = filtered.sum { |row| row[:delivered_amount] }

        {
          expected_total: expected,
          delivered_total: delivered,
          remaining_total: [ expected - delivered, 0 ].max,
          pct: pct(delivered, expected)
        }
      end

      def variable_income_row?(row)
        row[:classification] != "base"
      end

      def execution_status(realized, expected)
        return "unplanned" if expected.to_i <= 0 && realized.to_i.positive?
        return "covered" if expected.to_i.positive? && realized.to_i >= expected.to_i
        return "partial" if realized.to_i.positive?

        "pending"
      end

      def pct(realized, expected)
        expected = expected.to_i
        return 0 if expected <= 0

        ((realized.to_i.to_f / expected) * 100).round
      end

      # ── Burn rate ────────────────────────────────────────────────────────────

      def build_burn_rate(account_id, month, year, budgets, now_col)
        return nil if budgets.empty?

        days_in_month = Date.new(year, month, -1).day
        days_elapsed  = [ now_col.day, days_in_month ].min

        # Gastos reales por categoría (confirmados + pending, sin aportes a bolsillos)
        spent_by_cat = ::Transaction
          .where(account_id: account_id, month: month, year: year, transaction_type: "expense")
          .where(status: %w[confirmed pending])
          .where(sinking_fund_id: nil)
          .where.not(category_id: nil)
          .group(:category_id)
          .sum(:amount)

        # Gastos por subcategoría con nombre, directo desde transacciones via JOIN
        subcat_rows = ::Transaction
          .where(account_id: account_id, month: month, year: year, transaction_type: "expense")
          .where(status: %w[confirmed pending])
          .where(sinking_fund_id: nil)
          .where.not(subcategory_id: nil)
          .joins(:subcategory)
          .group("transactions.category_id", "transactions.subcategory_id", "subcategories.name")
          .sum("transactions.amount")
          .map { |(cat_id, sub_id, sub_name), spent|
            { category_id: cat_id, subcategory_id: sub_id, subcategory: sub_name, spent: spent }
          }

        subcat_by_cat = subcat_rows.group_by { |r| r[:category_id] }

        # Presupuesto a nivel subcategoría (opcional — $0 si no hay)
        budget_by_subcat = budgets
          .reject { |b| b[:subcategory_id].nil? }
          .each_with_object({}) { |b, h| h[b[:subcategory_id]] = b[:amount_limit].to_i }

        # Agrupar presupuestos por categoría sumando sus subcategorías.
        budget_by_cat = budgets
          .reject { |b| b[:category_id].nil? }
          .group_by { |b| b[:category_id] }
          .transform_values do |rows|
            {
              category_name: rows.first[:category_name],
              category_type: rows.first[:category_type],
              amount_limit:  rows.sum { |b| b[:amount_limit].to_i }
            }
          end

        categories = budget_by_cat.map do |cat_id, cat|
          spent     = spent_by_cat[cat_id].to_i
          budget    = cat[:amount_limit]
          behavior  = financial_behavior_for(
            category_type: cat[:category_type],
            category_code: cat[:category_type],
            name: cat[:category_name]
          )
          projected = days_elapsed > 0 ? (spent.to_f / days_elapsed * days_in_month).round : 0
          pct       = budget > 0 ? (projected.to_f / budget * 100).round : 0
          primary_metric = category_primary_metric(
            behavior: behavior,
            name: cat[:category_name],
            budget: budget,
            spent: spent,
            projected: projected,
            days_elapsed: days_elapsed,
            days_in_month: days_in_month
          )
          on_track  = primary_metric[:status] != "critical"
          alert     = %w[warning critical].include?(primary_metric[:status]) ? primary_metric[:body] : nil

          subcategories = (subcat_by_cat[cat_id] || []).map do |row|
            row.merge(budget: budget_by_subcat.fetch(row[:subcategory_id], 0))
          end

          {
            category:      cat[:category_name],
            category_type: cat[:category_type],
            category_id:   cat_id,
            budget:        budget,
            spent:         spent,
            projected:     projected,
            pct:           pct,
            behavior:      behavior,
            primary_metric: primary_metric,
            on_track:      on_track,
            alert:         alert,
            subcategories: subcategories
          }
        end

        {
          days_elapsed:  days_elapsed,
          days_in_month: days_in_month,
          categories:    categories
        }
      end

      def financial_behavior_for(category_type:, category_code: nil, subcategory_code: nil, name: nil)
        text = [ category_type, category_code, subcategory_code, name ].compact.join(" ").downcase

        return "debt_payment" if text.match?(/debt|deuda|credit|cr[eé]dito|prestamo|pr[eé]stamo|loan|tarjeta/)
        return "savings_goal" if text.match?(/saving|savings|ahorro|inversi[oó]n|investment|fondo|emergencia/)
        return "fixed_once" if text.match?(/rent|arriendo|alquiler|seguro|insurance|predial|matr[ií]cula/)
        return "fixed_recurring" if text.match?(/subscription|suscrip|netflix|spotify|internet|celular|phone|gimnasio|gym|servicio|utility|utilities/)
        return "variable_spiky" if text.match?(/health|salud|ropa|regalo|gift|reparaci[oó]n|repair|imprevisto|travel|viaje/)
        return "variable_linear" if text.match?(/food|comida|groceries|mercado|transport|transporte|dining|domicilio|restaurant|cafe|caf[eé]|snack|salida/)

        case category_type.to_s
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

      def category_primary_metric(behavior:, name:, budget:, spent:, projected:, days_elapsed:, days_in_month:)
        ratio = budget.to_i.positive? ? spent.to_f / budget.to_i : 0
        projected_over = projected.to_i - budget.to_i

        case behavior
        when "variable_linear"
          status = if budget.to_i.positive? && projected > budget
                     "critical"
          elsif budget.to_i.positive? && ratio >= month_progress_ratio(days_elapsed, days_in_month) + 0.2
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
            budget: budget
          }
        when "fixed_once", "fixed_recurring"
          pending = [ budget.to_i - spent.to_i, 0 ].max
          status = pending.positive? ? "warning" : "comfortable"
          {
            kind: "payment_status",
            status: status,
            title: pending.positive? ? "Pago pendiente" : "Pago cubierto",
            body: pending.positive? ?
              "Aún faltan #{format_cop(pending)} por cubrir en #{name}." :
              "#{name} ya está cubierto este mes.",
            value: pending,
            budget: budget
          }
        when "savings_goal"
          pct = budget.to_i.positive? ? ((spent.to_f / budget.to_i) * 100).round : 0
          {
            kind: "goal_progress",
            status: pct >= 100 ? "comfortable" : pct >= 60 ? "warning" : "critical",
            title: "Avance de meta",
            body: "Llevas #{pct}% de la meta mensual.",
            value: pct,
            budget: budget
          }
        when "debt_payment"
          pct = budget.to_i.positive? ? ((spent.to_f / budget.to_i) * 100).round : 0
          {
            kind: "debt_progress",
            status: spent.to_i.positive? ? "comfortable" : "warning",
            title: spent.to_i.positive? ? "Pago a deuda registrado" : "Pago pendiente",
            body: spent.to_i.positive? ?
              "Este pago ayuda a reducir deuda y sostiene tu plan." :
              "Todavía no hay pago registrado para esta deuda.",
            value: pct,
            budget: budget
          }
        else
          pct = budget.to_i.positive? ? ((spent.to_f / budget.to_i) * 100).round : 0
          status = pct >= 100 ? "critical" : pct >= 70 ? "warning" : "comfortable"
          {
            kind: "spiky_context",
            status: status,
            title: status == "comfortable" ? "Gasto puntual bajo control" : "Gasto puntual relevante",
            body: "Este gasto consumió #{pct}% del presupuesto asignado.",
            value: pct,
            budget: budget
          }
        end
      end

      def month_progress_ratio(days_elapsed, days_in_month)
        return 0 if days_in_month.to_i <= 0

        days_elapsed.to_f / days_in_month.to_i
      end

      # ── Debts summary ─────────────────────────────────────────────────────────

      def build_debts_summary(debts)
        active = debts.select { |d| d[:status] == "active" }
        return nil if active.empty?

        total_balance    = active.sum { |d| d[:current_balance] }
        monthly_payments = active.sum { |d| d[:monthly_payment] }

        # Snowball: menor saldo primero
        recommended = active.min_by { |d| d[:current_balance] }

        {
          total_balance:       total_balance,
          monthly_payments:    monthly_payments,
          recommended_payment: recommended ? {
            id:       recommended[:id],
            name:     recommended[:name],
            balance:  recommended[:current_balance],
            strategy: "snowball"
          } : nil
        }
      end

      # ── Financial context summary ─────────────────────────────────────────────

      def build_monthly_plan_summary(plan)
        return nil unless plan

        {
          id:                       plan[:id],
          status:                   plan[:status],
          mode:                     plan[:mode],
          base_budget_income:       plan[:base_budget_income],
          expected_variable_income: plan[:expected_variable_income],
          recurring_obligations_total: plan[:recurring_obligations_total],
          debt_minimums_total:      plan[:debt_minimums_total],
          discretionary_limit:      plan[:discretionary_limit],
          overflow_rule:            plan[:overflow_rule],
          overflow_rule_detail:     plan[:overflow_rule_detail],
          reward_pct:               plan[:reward_pct],
          debt_strategy:            plan[:debt_strategy],
          assumptions:              plan[:assumptions],
          confirmed_at:             plan[:confirmed_at]
        }
      end

      def build_overflow_status(
        plan,
        balance,
        ctx,
        debts,
        income_sources = [],
        realized_income_by_source = {},
        carryover_from_previous_month = 0
      )
        return nil unless plan

        base_budget_income = plan[:base_budget_income].to_i
        confirmed_income   = balance[:income_confirmed].to_i
        expected_variable_income = plan[:expected_variable_income].to_i
        realized_expected_variable_income = realized_expected_variable_income(
          income_sources,
          realized_income_by_source,
          expected_variable_income
        )
        realized_overflow = [
          confirmed_income - base_budget_income - realized_expected_variable_income,
          0
        ].max
        remaining_expected_overflow = [
          expected_variable_income - realized_expected_variable_income,
          0
        ].max
        target = overflow_target_for(plan, ctx, debts)

        {
          rule:                              plan[:overflow_rule],
          rule_detail:                       plan[:overflow_rule_detail] || {},
          base_budget_income:                base_budget_income,
          confirmed_income:                  confirmed_income,
          expected_variable_income:          expected_variable_income,
          realized_expected_variable_income: realized_expected_variable_income,
          realized_overflow:                 realized_overflow,
          remaining_expected_overflow:       remaining_expected_overflow,
          status:                            overflow_status(realized_overflow),
          suggested_destination:             target,
          suggested_action:                  overflow_action(
            plan,
            realized_overflow,
            target,
            realized_expected_variable_income,
            remaining_expected_overflow
          )
        }
      end

      def overflow_status(realized_overflow)
        realized_overflow.positive? ? "available" : "waiting"
      end

      def build_context_summary(ctx, plan, debts)
        return nil unless ctx

        {
          phase:               ctx[:phase],
          strategy:            ctx[:strategy],
          monthly_plan_status: plan&.dig(:status) || "missing"
        }
      end

      def overflow_target_for(plan, ctx, debts)
        case plan[:overflow_rule]
        when "debt"
          active_debts = debts.select { |d| d[:status] == "active" }
          return nil if active_debts.empty?

          strategy = plan[:debt_strategy].presence || ctx&.dig(:strategy)
          target = strategy == "avalanche" ?
            active_debts.max_by { |d| d[:interest_rate].to_f } :
            active_debts.min_by { |d| d[:current_balance].to_i }

          {
            type: "debt",
            debt_id: target[:id],
            debt_name: target[:name],
            strategy: strategy.presence || "snowball"
          }
        when "emergency_fund"
          { type: "emergency_fund", label: "colchón de seguridad" }
        when "investment"
          { type: "investment", label: "inversión / construcción de futuro" }
        when "mixed"
          { type: "mixed", label: "mix entre deuda, colchón e inversión" }
        else
          nil
        end
      end

      def overflow_action(
        plan,
        realized_overflow,
        target,
        realized_expected_variable_income = 0,
        remaining_expected_overflow = 0
      )
        if realized_overflow <= 0
          if realized_expected_variable_income.positive?
            if remaining_expected_overflow.positive?
              return "Ya entraron #{format_cop(realized_expected_variable_income)} de ingresos variables proyectados; faltan #{format_cop(remaining_expected_overflow)} por materializarse. No hay overflow adicional confirmado."
            end

            return "Los ingresos variables proyectados ya se materializaron. No hay overflow adicional confirmado por encima del plan."
          end

          return "Todavía no hay ingreso extra confirmado sobre la base del plan."
        end

        case plan[:overflow_rule]
        when "debt"
          debt_name = target&.dig(:debt_name) || "deuda prioritaria"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base; según tu plan debería ir a #{debt_name}."
        when "emergency_fund"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. Reforzá tu colchón."
        when "investment"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. Disponible para inversión."
        when "mixed"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. Repartilo sin inflar el presupuesto base."
        else
          nil
        end
      end

      def format_cop(amount)
        "$#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse}"
      end

      def income_realized_by_source(account_id, month, year)
        ::Transaction
          .where(
            account_id: account_id,
            month: month,
            year: year,
            transaction_type: "income",
            status: "confirmed"
          )
          .where.not(income_source_id: nil)
          .group(:income_source_id)
          .sum(:amount)
      end

      def necessary_transactions_for_burn(account_id, today)
        cutoff = today - 31
        ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed")
          .joins(:category)
          .where(categories: { category_type: "necessary" })
          .where(
            "(year > :cy) OR (year = :cy AND month >= :cm)",
            cy: cutoff.year, cm: cutoff.month
          )
          .pluck(:amount, :date, :year)
          .filter_map do |amount, date_str, yr|
            next unless date_str.present?
            day, mon = date_str.to_s.split("/").map(&:to_i)
            next unless day&.positive? && mon&.positive?
            date = Date.new(yr, mon, day) rescue nil
            next unless date
            { amount: amount, date: date }
          end
      end

      def applies_to_period?(metadata, period)
        data = (metadata || {}).to_h.stringify_keys
        return true if data["applies_to_period"].to_s == period.strftime("%Y-%m")

        data["applies_to_month"].to_i == period.month &&
          data["applies_to_year"].to_i == period.year
      end

      def realized_expected_variable_income(income_sources, realized_income_by_source, expected_variable_income)
        realized = Array(income_sources)
          .select { |source| source[:active] && variable_income_source?(source) }
          .sum do |source|
            source_id = source[:id]
            amount = realized_income_by_source.fetch(source_id, realized_income_by_source[source_id.to_s]).to_i
            expected = source[:expected_amount].to_i
            expected.positive? ? [ amount, expected ].min : amount
          end

        expected_variable_income.positive? ? [ realized, expected_variable_income ].min : realized
      end

      def variable_income_source?(source)
        source[:classification] == "variable" || source[:is_variable] == true
      end

      def income_matcher
        @income_matcher ||= Finanzas::Interactors::MatchIncomeSource.new
      end

      def structure_detector
        @structure_detector ||= Finanzas::Interactors::DetectTransactionStructure.new
      end

      # ── Repos ─────────────────────────────────────────────────────────────────

      def txn_repo
        @txn_repo ||= Finanzas::Repositories::TransactionRepository.new
      end

      def budget_repo
        @budget_repo ||= Finanzas::Repositories::BudgetRepository.new
      end

      def debt_repo
        @debt_repo ||= Finanzas::Repositories::DebtRepository.new
      end

      def ctx_repo
        @ctx_repo ||= Finanzas::Repositories::FinancialContextRepository.new
      end

      def plan_repo
        @plan_repo ||= Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      end

      def income_source_repo
        @income_source_repo ||= Finanzas::Repositories::IncomeSourceRepository.new
      end

      # Saldo acumulado real hasta el fin del mes anterior.
      # Suma todas las transacciones confirmadas de todos los meses previos al período consultado.
      # No usa execution_snapshot.overflow_amount porque ese valor representa dinero deployable
      # según reglas del plan, no caja real arrastrada al siguiente mes.
      def previous_month_carryover(account_id, month, year)
        prev = Date.new(year, month, 1).prev_month

        result = ::Transaction
          .where(account_id: account_id, status: "confirmed")
          .where("year < :y OR (year = :y AND month <= :m)", y: prev.year, m: prev.month)
          .group(:transaction_type)
          .sum(:amount)

        result.fetch("income", 0) - result.fetch("expense", 0)
      end
    end
  end
end
