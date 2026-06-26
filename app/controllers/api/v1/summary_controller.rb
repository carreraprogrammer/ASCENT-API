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

        # Saldo acumulado derivado de las transacciones (fuente de verdad). NO usamos
        # la columna accounts.confirmed_balance: es un cache incremental que puede
        # desincronizarse (un write que se salta el repo, o la regla de meses
        # solo-ingreso) y ya causó un margen libre falso de -$4M. El cálculo
        # autoritativo respeta la misma definición que el seed de la migración.
        account_confirmed_balance     = txn_repo.confirmed_balance(account_id: account_id)
        carryover_from_previous_month = account_confirmed_balance - balance[:balance_confirmed].to_i
        balance = balance.merge(
          carryover_from_previous_month: carryover_from_previous_month,
          net_balance: account_confirmed_balance
        )

        confirmed_balance = account_confirmed_balance
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
                     carryover_from_previous_month,
                     account_id, month, year
                   )

        render json: {
          period:            { month: month, year: year },
          balance:           balance,
          month_execution:   build_month_execution(account_id, month, year, income_sources),
          burn_rate:         burn_rate_calculator.call(account_id: account_id, month: month, year: year, budgets: budgets, today: now_col.to_date),
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
            subcategory_icon: obligation.subcategory&.icon,
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
        carryover_from_previous_month = 0,
        account_id = nil,
        month = nil,
        year = nil
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

        # YNAB regla 1 — "asigná cada peso". El ingreso que no cabe en la base
        # (prima, bono, freelance extra) no es sobregasto: es plata por asignar.
        # Si el usuario ya la mandó a deuda o al colchón, eso es asignación
        # cumplida, no un castigo. Hacemos el overflow simétrico: medimos cuánto
        # del extra YA se desplegó a prioridades para no pedir mover algo dos veces.
        #
        # Solo cuenta lo que va POR ENCIMA de lo que el plan base ya destina a esa
        # prioridad (los mínimos de deuda son base, no overflow). Sin esto, alguien
        # que solo paga sus mínimos parecería haber asignado su extra sin moverlo.
        deployment = account_id ?
          overflow_deployment_for(account_id, month, year) :
          { to_debt: 0, to_savings: 0, total: 0 }
        base_debt_allocation = plan[:debt_minimums_total].to_i
        assigned_breakdown = {
          to_debt:    [ deployment[:to_debt] - base_debt_allocation, 0 ].max,
          to_savings: deployment[:to_savings]
        }
        assignable_total             = assigned_breakdown[:to_debt] + assigned_breakdown[:to_savings]
        overflow_assigned            = [ assignable_total, realized_overflow ].min
        overflow_remaining_to_assign = [ realized_overflow - overflow_assigned, 0 ].max

        {
          rule:                              plan[:overflow_rule],
          rule_detail:                       plan[:overflow_rule_detail] || {},
          base_budget_income:                base_budget_income,
          confirmed_income:                  confirmed_income,
          expected_variable_income:          expected_variable_income,
          realized_expected_variable_income: realized_expected_variable_income,
          realized_overflow:                 realized_overflow,
          remaining_expected_overflow:       remaining_expected_overflow,
          deployed_to_priorities:            deployment,
          overflow_assigned:                 overflow_assigned,
          overflow_assigned_breakdown:       assigned_breakdown,
          overflow_remaining_to_assign:      overflow_remaining_to_assign,
          status:                            overflow_status(realized_overflow, overflow_remaining_to_assign),
          suggested_destination:             target,
          suggested_action:                  overflow_action(
            plan,
            realized_overflow,
            target,
            realized_expected_variable_income,
            remaining_expected_overflow,
            assigned_breakdown,
            overflow_assigned,
            overflow_remaining_to_assign
          )
        }
      end

      # Cuánto del ingreso extra del mes ya fue asignado a prioridades reales:
      # abono a deuda (debt_id) y aporte a ahorro/construcción (sinking_fund o
      # categoría investment). Reutiliza las señales de agencia que ya existen;
      # no introduce un eje contable nuevo (ver principios.md §1).
      def overflow_deployment_for(account_id, month, year)
        scope = ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed", month: month, year: year)
          .left_joins(:category)

        to_debt = scope.where.not(debt_id: nil).sum(:amount).to_i
        to_savings = scope
          .where(debt_id: nil)
          .where(
            "transactions.savings_goal_id IS NOT NULL OR transactions.sinking_fund_id IS NOT NULL " \
            "OR categories.category_type = ?", "investment"
          )
          .sum(:amount).to_i

        { to_debt: to_debt, to_savings: to_savings, total: to_debt + to_savings }
      end

      def overflow_status(realized_overflow, remaining_to_assign = nil)
        return "waiting" unless realized_overflow.positive?
        return "available" if remaining_to_assign.nil?

        remaining_to_assign.positive? ? "available" : "deployed"
      end

      def build_context_summary(ctx, plan, debts)
        return nil unless ctx

        {
          phase:                     ctx[:phase],
          strategy:                  ctx[:strategy],
          monthly_plan_status:       plan&.dig(:status) || "missing",
          monthly_goal_contribution: ctx[:monthly_goal_contribution]
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
        remaining_expected_overflow = 0,
        deployment = { to_debt: 0, to_savings: 0, total: 0 },
        overflow_assigned = 0,
        overflow_remaining_to_assign = nil
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

        remaining = overflow_remaining_to_assign.nil? ? realized_overflow : overflow_remaining_to_assign

        # Ya asignó todo el extra a prioridades: es asignación cumplida, no castigo.
        if overflow_assigned.positive? && remaining <= 0
          return "Entraron #{format_cop(realized_overflow)} por encima de tu base y ya los asignaste #{overflow_deployment_phrase(deployment)}. No queda nada por mover: cada peso extra tiene destino."
        end

        # Asignó una parte: reconocer lo hecho y nombrar solo lo que falta.
        if overflow_assigned.positive?
          return "Entraron #{format_cop(realized_overflow)} extra; ya asignaste #{format_cop(overflow_assigned)} #{overflow_deployment_phrase(deployment)}. Quedan #{format_cop(remaining)} por asignar#{overflow_target_suffix(plan, target)}."
        end

        # Nada asignado todavía: sugerir destino según el plan.
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

      def overflow_deployment_phrase(deployment)
        parts = []
        parts << "#{format_cop(deployment[:to_debt])} a deuda"   if deployment[:to_debt].to_i.positive?
        parts << "#{format_cop(deployment[:to_savings])} a tu colchón/construcción" if deployment[:to_savings].to_i.positive?
        return "a tus prioridades" if parts.empty?

        "(#{parts.join(', ')})"
      end

      def overflow_target_suffix(plan, target)
        case plan[:overflow_rule]
        when "debt"        then " a #{target&.dig(:debt_name) || 'tu deuda prioritaria'}"
        when "emergency_fund" then " a tu colchón"
        when "investment"  then " a inversión"
        else ""
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

      def ledger_confirmed_balance(account_id)
        rows = ::Transaction
          .where(account_id: account_id, status: "confirmed")
          .group(:transaction_type)
          .sum(:amount)

        rows["income"].to_i - rows["expense"].to_i
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
            date = parse_burn_date(date_str, yr)
            next unless date
            { amount: amount, date: date }
          end
      end

      # El campo `date` se guarda en ISO (YYYY-MM-DD) desde CreateTransaction, pero
      # registros antiguos pueden venir en DD/MM. Soporta ambos para no descartar
      # transacciones (lo que dejaba el ritmo diario pegado en el fallback de 30k).
      def parse_burn_date(date_str, year)
        return nil unless date_str.present?
        str = date_str.to_s
        if str.match?(/\A\d{4}-\d{2}-\d{2}/)
          Date.parse(str) rescue nil
        else
          day, mon = str.split("/").map(&:to_i)
          return nil unless day&.positive? && mon&.positive?
          Date.new(year, mon, day) rescue nil
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

      def burn_rate_calculator
        @burn_rate_calculator ||= Finanzas::Interactors::BurnRateCalculator.new
      end

      def income_source_repo
        @income_source_repo ||= Finanzas::Repositories::IncomeSourceRepository.new
      end

    end
  end
end
