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
        credit_card_pending  = ::Transaction
                                 .where(account_id: account_id, payment_source: "credit_card",
                                        credit_card_status: "pending")
                                 .sum(:amount)
        liquidity            = Finanzas::Interactors::LiquidityProjection.new.call(
                                 plan:                plan,
                                 balance:             balance,
                                 income_sources:      income_sources,
                                 realized_income_by_source: realized_income_by_source,
                                 credit_card_pending: credit_card_pending,
                                 today:               now_col.to_date
                               )

        savings_goals = ::SavingsGoal
          .where(account_id: account_id, status: "active")
          .order(priority: :asc)
          .map { |g| { name: g.name, target_amount: g.target_amount,
                       current_amount: g.current_amount,
                       monthly_contribution_needed: g.monthly_contribution_needed,
                       target_date: g.target_date, status: g.status } }

        render json: {
          period:               { month: month, year: year },
          balance:              balance,
          burn_rate:            build_burn_rate(account_id, month, year, budgets, now_col),
          debts:                build_debts_summary(debts),
          monthly_plan:         build_monthly_plan_summary(plan),
          overflow_status:      build_overflow_status(
                                  plan,
                                  balance,
                                  ctx,
                                  debts,
                                  liquidity,
                                  income_sources,
                                  realized_income_by_source
                                ),
          financial_context:    build_context_summary(ctx, plan, debts, liquidity),
          liquidity:            liquidity,
          credit_card_pending:  credit_card_pending,
          savings_goals:        savings_goals
        }
      end

      private

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
        realized_income_by_source = {}
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
        safe_to_deploy = liquidity&.dig(:safe_to_deploy).to_i
        deployable_overflow = [realized_overflow, safe_to_deploy].min
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

      def build_context_summary(ctx, plan, debts, liquidity = nil)
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

        safe_to_deploy        = liquidity&.dig(:safe_to_deploy).to_i
        deployable_this_cycle = liquidity&.dig(:deployable_this_cycle).to_i
        active_debts          = debts.select { |d| d[:status] == "active" }
        recommended_action = build_recommended_action(ctx, active_debts, safe_to_deploy, deployable_this_cycle)

        {
          phase:                    ctx[:phase],
          strategy:                 ctx[:strategy],
          monthly_plan_status:      plan&.dig(:status) || "missing",
          monthly_surplus_estimate: surplus,
          recommended_action:       recommended_action
        }
      end

      def build_recommended_action(ctx, active_debts, safe_to_deploy, deployable_this_cycle = 0)
        return nil if active_debts.empty?

        if safe_to_deploy <= 0
          return "Cubre tus obligaciones del próximo ciclo primero. No hay margen para mover dinero ahora."
        end

        if deployable_this_cycle <= 0
          return "El próximo ciclo está cubierto. En cuanto llegue el ingreso pendiente, tendrás margen para abonar a tus deudas."
        end

        case ctx[:phase]
        when "debt_payoff"
          target = ctx[:strategy] == "snowball" ?
            active_debts.min_by { |d| d[:current_balance] } :
            active_debts.max_by { |d| d[:interest_rate] }
          return nil unless target

          abono  = [deployable_this_cycle, target[:current_balance]].min
          months = abono > 0 ? (target[:current_balance].to_f / abono).ceil : "?"
          "Si el ingreso pendiente llega esta semana, podés destinar #{format_cop(deployable_this_cycle)} a deuda. Abona #{format_cop(abono)} al #{target[:name]} — lo liquidas en #{months} #{"mes".pluralize(months)} (#{ctx[:strategy]})."
        else
          nil
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
    end
  end
end
