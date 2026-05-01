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
        prepaid_recurring_obligations = prepaid_recurring_obligations_total(account_id, month, year)
        credit_card_pending  = ::Transaction
                                 .where(account_id: account_id, payment_source: "credit_card",
                                        credit_card_status: "pending")
                                 .sum(:amount)
        carryover_from_previous_month = previous_month_carryover(account_id, month, year)
        balance = balance.merge(
          carryover_from_previous_month: carryover_from_previous_month,
          net_balance: balance[:balance_confirmed] + carryover_from_previous_month
        )
        liquidity            = Finanzas::Interactors::LiquidityProjection.new.call(
                                 plan:                         plan,
                                 balance:                      balance,
                                 income_sources:               income_sources,
                                 realized_income_by_source:    realized_income_by_source,
                                 credit_card_pending:          credit_card_pending,
                                 prepaid_recurring_obligations: prepaid_recurring_obligations,
                                 carryover_from_previous_month: carryover_from_previous_month,
                                 today:                        now_col.to_date
                               )

        savings_goals = ::SavingsGoal
          .where(account_id: account_id, status: "active")
          .order(priority: :asc)
          .map { |g| { name: g.name, target_amount: g.target_amount,
                       current_amount: g.current_amount,
                       monthly_contribution_needed: g.monthly_contribution_needed,
                       target_date: g.target_date, status: g.status } }

        overflow = build_overflow_status(
                     plan, balance, ctx, debts, liquidity,
                     income_sources, realized_income_by_source,
                     carryover_from_previous_month
                   )

        render json: {
          period:               { month: month, year: year },
          balance:              balance,
          month_execution:      build_month_execution(account_id, month, year, income_sources),
          burn_rate:            build_burn_rate(account_id, month, year, budgets, now_col),
          debts:                build_debts_summary(debts),
          monthly_plan:         build_monthly_plan_summary(plan),
          overflow_status:      overflow,
          financial_context:    build_context_summary(ctx, plan, debts, liquidity, overflow&.dig(:deployable_overflow).to_i),
          liquidity:            liquidity,
          credit_card_pending:  credit_card_pending,
          savings_goals:        savings_goals
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
        days_elapsed  = [now_col.day, days_in_month].min

        # Gastos reales por categoría (confirmados + pending)
        spent_by_cat = ::Transaction
          .where(account_id: account_id, month: month, year: year, transaction_type: "expense")
          .where(status: %w[confirmed pending])
          .where.not(category_id: nil)
          .group(:category_id)
          .sum(:amount)

        # Agrupar presupuestos por categoría sumando sus subcategorías.
        # budgets puede tener N filas por categoría (una por subcategoría) cuando el wizard
        # guarda a nivel subcategoría. Si comparamos el presupuesto individual de cada
        # subcategoría contra el gasto total de la categoría obtenemos porcentajes absurdos.
        budget_by_cat = budgets
          .reject { |b| b[:category_id].nil? }
          .group_by { |b| b[:category_id] }
          .transform_values do |rows|
            {
              category_name: rows.first[:category_name],
              amount_limit:  rows.sum { |b| b[:amount_limit].to_i }
            }
          end

        categories = budget_by_cat.map do |cat_id, cat|
          spent     = spent_by_cat[cat_id].to_i
          budget    = cat[:amount_limit]
          projected = days_elapsed > 0 ? (spent.to_f / days_elapsed * days_in_month).round : 0
          pct       = budget > 0 ? (projected.to_f / budget * 100).round : 0
          on_track  = projected <= budget
          alert     = !on_track ? "⚠️ #{cat[:category_name]}: vas a #{format_cop(projected)} proyectados vs presupuesto de #{format_cop(budget)}" : nil

          {
            category:    cat[:category_name],
            category_id: cat_id,
            budget:      budget,
            spent:       spent,
            projected:   projected,
            pct:         pct,
            on_track:    on_track,
            alert:       alert
          }
        end

        {
          days_elapsed:  days_elapsed,
          days_in_month: days_in_month,
          categories:    categories
        }
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
          protected_buffer_amount:  plan[:protected_buffer_amount],
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
        liquidity = nil,
        income_sources = [],
        realized_income_by_source = {},
        carryover_from_previous_month = 0
      )
        return nil unless plan

        base_budget_income = plan[:base_budget_income].to_i
        confirmed_income = balance[:income_confirmed].to_i
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
        safe_to_deploy    = liquidity&.dig(:safe_to_deploy).to_i
        confirmed_balance = balance[:income_confirmed].to_i - balance[:expense_confirmed].to_i +
                            carryover_from_previous_month.to_i
        protected_buffer  = plan[:protected_buffer_amount].to_i
        # El deployable está limitado por lo que queda del balance DESPUÉS de reservar el buffer.
        # Si el balance actual no supera el buffer, no hay nada desplegable hoy — el buffer
        # cubre la brecha hasta el próximo ingreso (ej: quincena) antes de que venzan obligaciones.
        deployable_cap      = [confirmed_balance - protected_buffer, 0].max
        deployable_overflow = [realized_overflow, safe_to_deploy, deployable_cap].min
        blocked_by_liquidity = realized_overflow.positive? && deployable_overflow <= 0
        target = overflow_target_for(plan, ctx, debts)
        remaining_expected_overflow = [
          expected_variable_income - realized_expected_variable_income,
          0
        ].max

        {
          rule: plan[:overflow_rule],
          rule_detail: plan[:overflow_rule_detail] || {},
          base_budget_income: base_budget_income,
          confirmed_income: confirmed_income,
          expected_variable_income: expected_variable_income,
          realized_expected_variable_income: realized_expected_variable_income,
          realized_overflow: realized_overflow,
          safe_to_deploy: safe_to_deploy,
          deployable_overflow: deployable_overflow,
          blocked_by_liquidity: blocked_by_liquidity,
          remaining_expected_overflow: remaining_expected_overflow,
          status: overflow_status(realized_overflow, deployable_overflow),
          suggested_destination: target,
          suggested_action: overflow_action(
            plan,
            realized_overflow,
            deployable_overflow,
            target,
            realized_expected_variable_income,
            remaining_expected_overflow
          )
        }
      end

      def overflow_status(realized_overflow, deployable_overflow)
        return "waiting" unless realized_overflow.positive?
        return "blocked_by_liquidity" unless deployable_overflow.positive?

        "available"
      end

      def build_context_summary(ctx, plan, debts, liquidity = nil, deployable_overflow = 0)
        return nil unless ctx

        # monthly_surplus_estimate se mantiene para referencia histórica (calculado desde el plan).
        # La recomendación de acción usa safe_to_deploy de liquidity — nunca el surplus teórico.
        surplus = if plan
          plan[:base_budget_income].to_i -
            plan[:recurring_obligations_total].to_i -
            plan[:debt_minimums_total].to_i -
            plan[:protected_buffer_amount].to_i -
            plan[:discretionary_limit].to_i
        end

        safe_to_deploy    = liquidity&.dig(:safe_to_deploy).to_i
        active_debts      = debts.select { |d| d[:status] == "active" }
        recommended_action = build_recommended_action(ctx, active_debts, safe_to_deploy, deployable_overflow)

        {
          phase:                    ctx[:phase],
          strategy:                 ctx[:strategy],
          monthly_plan_status:      plan&.dig(:status) || "missing",
          monthly_surplus_estimate: surplus,
          recommended_action:       recommended_action
        }
      end

      def build_recommended_action(ctx, active_debts, safe_to_deploy, _deployable_overflow = 0)
        return nil if active_debts.empty?

        # El sistema agrega ingreso mensual pero no modela el timing intra-mes
        # (quincenas, fechas de vencimiento de obligaciones). Dar un monto específico
        # de abono sin ese modelo produce recomendaciones irresponsables.
        # Solo se muestra el estado del ciclo; el insight del agente maneja la recomendación.
        if safe_to_deploy <= 0
          "Priorizá cubrir las obligaciones del próximo ciclo antes de mover dinero."
        else
          "El próximo ciclo está cubierto."
        end
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
        deployable_overflow,
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

        if deployable_overflow <= 0
          return "Entraron #{format_cop(realized_overflow)} por encima de tu base, pero no están libres para mover: primero hay que cubrir obligaciones próximas y el buffer."
        end

        case plan[:overflow_rule]
        when "debt"
          debt_name = target&.dig(:debt_name) || "deuda prioritaria"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. De eso, #{format_cop(deployable_overflow)} está disponible para mover; según tu plan debería ir a #{debt_name}."
        when "emergency_fund"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. De eso, #{format_cop(deployable_overflow)} está disponible para reforzar tu colchón."
        when "investment"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. De eso, #{format_cop(deployable_overflow)} está disponible para inversión."
        when "mixed"
          "Entraron #{format_cop(realized_overflow)} por encima de tu base. De eso, #{format_cop(deployable_overflow)} está disponible para repartir sin inflar tu presupuesto base."
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

      def prepaid_recurring_obligations_total(account_id, month, year)
        next_cycle = Date.new(year, month, 1).next_month

        ::Transaction
          .includes(:recurring_obligation)
          .where(
            account_id: account_id,
            month: month,
            year: year,
            transaction_type: "expense",
            status: "confirmed"
          )
          .where.not(recurring_obligation_id: nil)
          .select { |transaction| applies_to_period?(transaction.metadata, next_cycle) }
          .sum do |transaction|
            expected_amount = transaction.recurring_obligation&.amount.to_i
            expected_amount.positive? ? [ transaction.amount.to_i, expected_amount ].min : transaction.amount.to_i
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

      # Saldo neto acumulado de todos los meses confirmados anteriores al período consultado.
      # No depende de que el plan esté cerrado — usa las transacciones reales de la cuenta.
      def previous_month_carryover(account_id, month, year)
        prior = ::Transaction
          .where(account_id: account_id, status: "confirmed")
          .where("(year < :year) OR (year = :year AND month < :month)", year: year, month: month)

        income  = prior.where(transaction_type: "income").sum(:amount)
        expense = prior.where(transaction_type: "expense").sum(:amount)
        income - expense
      end
    end
  end
end
