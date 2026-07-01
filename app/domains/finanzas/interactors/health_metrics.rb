module Finanzas
  module Interactors
    # Calcula los ratios de salud financiera fundamentales del usuario.
    #
    # Basado en estándares CFP, metodología YNAB y Ramit Sethi CSP.
    # Ver specs/research/metodologias-coaching-financiero.md para definiciones y umbrales.
    #
    # Todos los porcentajes son sobre base_budget_income del plan mensual activo.
    # Si no hay plan activo, los ratios quedan como nil (no inventamos un denominador).
    class HealthMetrics
      AGE_OF_MONEY_SAMPLE = 10  # últimas N transacciones de egreso para el promedio

      # @param account_id [Integer]
      # @param month      [Integer] mes del plan de referencia (default: mes actual)
      # @param year       [Integer]
      # @return [Hash]
      def call(account_id:, month: nil, year: nil)
        today  = Date.today
        month  ||= today.month
        year   ||= today.year

        plan         = load_plan(account_id, month, year)
        obligations  = load_obligations(account_id)
        debts        = load_debts(account_id)
        goals        = load_goals(account_id)
        base_income  = plan&.base_budget_income.to_i
        ef           = emergency_fund_metrics(goals, obligations)

        {
          base_income:                  base_income,
          ratio_gastos_fijos:           ratio_gastos_fijos(obligations, base_income),
          emergency_fund:               ef,
          emergency_mode:               emergency_mode(obligations, base_income),
          tasa_ahorro:                  tasa_ahorro(goals, base_income),
          dti:                          dti(debts, base_income),
          age_of_money:                 age_of_money(account_id, today),
          coaching_priority:            coaching_priority(ef, debts),
        }
      end

      private

      # ── Modo Emergencia (RFC-0001 §3f) ──────────────────────────────────────
      # "Si pierdo el ingreso, ¿cuál es mi piso de supervivencia y cuánto libero?".
      # Agrupa las obligaciones recurrentes por tier de agencia (Category#tier):
      #   survival_floor = committed + necessary (lo que hay que seguir pagando)
      #   cuttable       = flexible (recurrentes que se pausarían en una crisis)
      # El gasto flexible del día a día se recorta también pero no vive en obligaciones;
      # acá se mide el piso fijo, que es lo accionable para dimensionar una emergencia.
      def emergency_mode(obligations, base_income)
        by_tier   = obligations.group_by { |o| o.category&.tier || "unknown" }
        committed = tier_sum(by_tier, "committed")
        necessary = tier_sum(by_tier, "necessary")
        flexible  = tier_sum(by_tier, "flexible")
        floor     = committed + necessary

        {
          survival_floor:      floor,
          committed_monthly:   committed,
          necessary_monthly:   necessary,
          cuttable_recurring:  flexible,
          base_income:         base_income,
          surplus_over_floor:  base_income.positive? ? base_income - floor : nil
        }
      end

      def tier_sum(by_tier, tier)
        (by_tier[tier] || []).sum { |o| o.amount.to_i }
      end

      # ── Ratio de gastos fijos (NC-4) ────────────────────────────────────────
      # Cuánto del ingreso base está comprometido en obligaciones recurrentes.
      # Incluye pagos de deuda porque son compromisos fijos igual.
      def ratio_gastos_fijos(obligations, base_income)
        total = obligations.sum { |o| o.amount.to_i }
        return { total_fixed: total, base_income: base_income, value: nil, status: "no_plan" } if base_income.zero?

        pct = (total.to_f / base_income * 100).round(1)
        {
          total_fixed:  total,
          base_income:  base_income,
          value:        pct,
          status:       classify_ratio_fijos(pct)
        }
      end

      # excellent ≤50% | healthy 51-65% | warning 66-75% | critical >75%
      def classify_ratio_fijos(pct)
        return "excellent" if pct <= 50
        return "healthy"   if pct <= 65
        return "warning"   if pct <= 75
        "critical"
      end

      # ── Fondo de emergencia (NC-3) ───────────────────────────────────────────
      # Usa bare-bones (obligaciones sin deuda) como denominador mensual.
      # El fondo de emergencia es lo que tienen en savings_goals de ese tipo,
      # o el balance de la cuenta si no hay una meta definida.
      def emergency_fund_metrics(goals, obligations)
        ef_goal    = goals.find { |g| g.name.to_s =~ /emergencia|emergency/i }
        ef_balance = ef_goal&.current_amount.to_i

        # Bare-bones = TODAS las obligaciones activas, incluyendo mínimos de deuda.
        # En una emergencia real (pérdida de ingreso) los mínimos de deuda
        # también hay que pagarlos — en Colombia, no pagarlos reporta a DataCrédito
        # y genera intereses de mora que empeoran la situación.
        bare_bones = obligations.sum { |o| o.amount.to_i }

        target_1m = bare_bones
        target_3m = bare_bones * 3
        target_6m = bare_bones * 6

        months = bare_bones > 0 ? (ef_balance.to_f / bare_bones).round(2) : 0

        {
          balance:         ef_balance,
          bare_bones_monthly: bare_bones,
          months_covered:  months,
          target_1m:       target_1m,
          target_3m:       target_3m,
          target_6m:       target_6m,
          gap_to_1m:       [ target_1m - ef_balance, 0 ].max,
          gap_to_3m:       [ target_3m - ef_balance, 0 ].max,
          gap_to_6m:       [ target_6m - ef_balance, 0 ].max,
          has_goal_defined: ef_goal.present?,
          status:          classify_emergency_fund(months)
        }
      end

      # none <0.5m | starter 0.5-1m | minimal 1-3m | healthy 3-6m | excellent >6m
      def classify_emergency_fund(months)
        return "none"      if months < 0.5
        return "starter"   if months < 1
        return "minimal"   if months < 3
        return "healthy"   if months < 6
        "excellent"
      end

      # ── Tasa de ahorro (NC-5) ────────────────────────────────────────────────
      # monthly_contribution de todas las metas activas / base_income.
      def tasa_ahorro(goals, base_income)
        total = goals.select { |g| g.status == "active" }.sum { |g| g.monthly_contribution.to_i }
        return { monthly_contribution: total, base_income: base_income, value: nil, status: "no_plan" } if base_income.zero?

        pct = (total.to_f / base_income * 100).round(1)
        {
          monthly_contribution: total,
          base_income:          base_income,
          value:                pct,
          status:               classify_savings_rate(pct)
        }
      end

      # insufficient <5% | basic 5-10% | healthy 10-15% | excellent >15%
      def classify_savings_rate(pct)
        return "insufficient" if pct < 5
        return "basic"        if pct < 10
        return "healthy"      if pct < 15
        "excellent"
      end

      # ── Prioridad de coaching (NC-3 + metodologías §4.3) ────────────────────
      # Fuente única de verdad para "¿a dónde va el excedente?". Los agentes
      # NUNCA deciden esto por su cuenta — consumen esta directiva tal cual.
      # Secuencia: fondo starter (1 mes) → deuda → fondo completo (3m) → invertir.
      def coaching_priority(ef, debts)
        months       = ef[:months_covered].to_f
        active_debts = debts.to_a # load_debts ya filtra status: active

        if months < 1
          {
            code:      "emergency_fund_starter",
            directive: "Todo excedente va al fondo de emergencia hasta cubrir 1 mes " \
                       "(faltan #{ef[:gap_to_1m]} COP). No sugerir abonos extra a deuda " \
                       "(solo mínimos) ni inversión.",
            reason:    "Fondo cubre #{months} meses (< 1 mes starter). NC-3: ningún marco " \
                       "recomienda atacar deuda o invertir sin colchón mínimo."
          }
        elsif active_debts.any?
          {
            code:      "debt_payoff",
            directive: "Fondo starter cubierto. El excedente ataca la deuda según la " \
                       "estrategia del usuario (snowball/avalanche). Mantener mínimos y " \
                       "no crecer el fondo más allá de 1 mes mientras haya deuda activa.",
            reason:    "Fondo cubre #{months} meses y hay #{active_debts.size} deuda(s) activa(s)."
          }
        elsif months < 3
          {
            code:      "complete_emergency_fund",
            directive: "Sin deudas activas. El excedente completa el fondo de emergencia " \
                       "hasta 3 meses (faltan #{ef[:gap_to_3m]} COP).",
            reason:    "Fondo cubre #{months} meses (< 3 meses suficientes) y no hay deuda."
          }
        else
          {
            code:      "invest",
            directive: "Fondo suficiente y sin deudas. El excedente puede ir a inversión — " \
                       "sin recomendar instrumentos específicos (no somos asesores).",
            reason:    "Fondo cubre #{months} meses (≥ 3) y no hay deuda activa."
          }
        end
      end

      # ── DTI — Debt-to-Income ratio (NC-6) ───────────────────────────────────
      # Pagos mínimos mensuales de deudas activas / base_income.
      # Denominador = ingreso BASE (no variable) — mide estrés real de caja.
      def dti(debts, base_income)
        total = debts.sum { |d| d.monthly_payment.to_i }
        return { monthly_payments: total, base_income: base_income, value: nil, status: "no_plan" } if base_income.zero?

        pct = (total.to_f / base_income * 100).round(1)
        {
          monthly_payments: total,
          base_income:      base_income,
          value:            pct,
          status:           classify_dti(pct)
        }
      end

      # safe ≤20% | warning 21-35% | stress >35%
      def classify_dti(pct)
        return "safe"    if pct <= 20
        return "warning" if pct <= 35
        "stress"
      end

      # ── Age of Money (YNAB Rule 4) ───────────────────────────────────────────
      # Días promedio entre cuándo entró el dinero y cuándo se gastó.
      # Target: ≥30 días = gastando dinero del ciclo anterior.
      #
      # Aproximación FIFO simplificada: para cada uno de los últimos N egresos,
      # encontramos el ingreso más reciente anterior a esa fecha y promediamos la diferencia.
      def age_of_money(account_id, today)
        recent_expenses = ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed")
          .where.not(year: nil, month: nil)
          .order(year: :desc, month: :desc, id: :desc)
          .limit(AGE_OF_MONEY_SAMPLE)
          .pluck(:amount, :date, :year, :month)
          .filter_map { |_, d, yr, mo| parse_transaction_date(d, yr, mo) }

        return nil if recent_expenses.size < 3

        recent_incomes = ::Transaction
          .where(account_id: account_id, transaction_type: "income", status: "confirmed")
          .where.not(year: nil, month: nil)
          .order(year: :desc, month: :desc, id: :desc)
          .limit(30)
          .pluck(:date, :year, :month)
          .filter_map { |d, yr, mo| parse_transaction_date(d, yr, mo) }
          .sort
          .reverse

        return nil if recent_incomes.empty?

        ages = recent_expenses.filter_map do |expense_date|
          prior_income = recent_incomes.find { |d| d <= expense_date }
          next unless prior_income

          (expense_date - prior_income).to_i
        end

        return nil if ages.empty?

        avg_days = (ages.sum.to_f / ages.size).round
        {
          days:   avg_days,
          sample: ages.size,
          status: classify_age_of_money(avg_days)
        }
      end

      # <14d paycheck-to-paycheck severo | 14-30d moderado | ≥30d rompió el ciclo
      def classify_age_of_money(days)
        return "paycheck_to_paycheck" if days < 14
        return "improving"            if days < 30
        "healthy"
      end

      # ── Parseo de fecha de transacción ──────────────────────────────────────
      # Las fechas en transactions pueden venir como "DD/MM" o "YYYY-MM-DD".
      def parse_transaction_date(date_str, year, month)
        return nil unless date_str.present? && year.present? && month.present?

        if date_str.to_s.include?("/")
          day = date_str.to_s.split("/").first.to_i
          return nil unless day.positive?
          Date.new(year.to_i, month.to_i, day) rescue nil
        elsif date_str.to_s =~ /\A\d{4}-\d{2}-\d{2}\z/
          Date.parse(date_str.to_s) rescue nil
        end
      end

      # ── Queries ──────────────────────────────────────────────────────────────

      def load_plan(account_id, month, year)
        # Busca el plan del mes solicitado; si no existe, usa el más reciente confirmado.
        ::MonthlyFinancialPlan
          .where(account_id: account_id, month: month, year: year)
          .where(status: %w[confirmed draft])
          .order(created_at: :desc)
          .first ||
          ::MonthlyFinancialPlan
            .where(account_id: account_id, status: "confirmed")
            .order(year: :desc, month: :desc)
            .first
      end

      def load_obligations(account_id)
        ::RecurringObligation.includes(:category).where(account_id: account_id, active: true)
      end

      def load_debts(account_id)
        ::Debt.where(account_id: account_id, status: :active)
      end

      def load_goals(account_id)
        ::SavingsGoal.where(account_id: account_id)
      end
    end
  end
end
