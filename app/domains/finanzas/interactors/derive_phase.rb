module Finanzas
  module Interactors
    # Deterministically derives the user's financial phase using Ramsey Baby Steps order.
    # Never reads FinancialContext.phase — derives from real financial data.
    #
    # Order:
    #   Step 1: seed emergency fund (fixed ~$1,000 USD, NOT one month of expenses)
    #   Step 2: Debt snowball (all active debts cleared)
    #   Step 3: 3-month emergency fund
    #   Step 4+: investing
    class DerivePhase
      # Baby Step 1 (Ramsey): fondo inicial FIJO y simbólico, no un mes de gastos.
      # ~$1.000 USD ≈ $4.000.000 COP. Umbral estable (no atado al tipo de cambio del día).
      # Fuente de verdad del monto semilla para todo el dominio (lo referencia HealthMetrics).
      SEED_EMERGENCY_FUND = 4_000_000
      def call(account_id:)
        explain(account_id: account_id)[:phase]
      end

      # Igual que #call pero devuelve también la RAZÓN legible y los datos que la
      # sustentan, para que la UI le explique al usuario por qué el coach dedujo
      # esta fase (transparencia con agencia). No persiste nada.
      def explain(account_id:)
        committed_monthly = fetch_committed_monthly(account_id)
        ef_balance        = fetch_ef_balance(account_id)
        has_active_debts  = fetch_has_active_debts(account_id)
        ef_months         = committed_monthly.positive? ? (ef_balance.to_f / committed_monthly).round(1) : nil

        phase = derive(committed_monthly, ef_balance, has_active_debts)

        {
          phase:             phase,
          reason:            reason_for(phase, committed_monthly, ef_balance, has_active_debts),
          committed_monthly: committed_monthly,
          ef_balance:        ef_balance,
          ef_months:         ef_months,
          has_active_debts:  has_active_debts
        }
      end

      private

      def derive(committed_monthly, ef_balance, has_active_debts)
        if has_active_debts
          # Step 1: colchón semilla FIJO antes de atacar la deuda. Solo aplica CON deuda:
          # es el buffer para no re-endeudarse en una emergencia mientras se paga agresivo.
          return "emergency_fund" if ef_balance < SEED_EMERGENCY_FUND

          # Step 2: liquidar toda la deuda
          return "debt_payoff"
        end

        # Sin deuda: se va directo al fondo de emergencia completo (el semilla es solo
        # la primera parte del mismo fondo, no un bolsillo aparte).
        if committed_monthly > 0
          # Step 3: fondo de emergencia de 3 meses de gastos esenciales
          return "emergency_fund" if ef_balance < 3 * committed_monthly
        end

        "investing"
      end

      # Razón legible (secuencia Ramsey) — el "por qué" de la fase deducida.
      def reason_for(phase, committed_monthly, ef_balance, has_active_debts)
        case phase
        when "emergency_fund"
          if has_active_debts && ef_balance < SEED_EMERGENCY_FUND
            "Con deuda activa, la prioridad (paso 1) es un colchón semilla de $#{SEED_EMERGENCY_FUND.to_s.reverse.scan(/\d{1,3}/).join('.').reverse} (~$1.000 USD) antes de atacar la deuda de forma agresiva."
          else
            "Tu colchón aún no cubre 3 meses de gastos fijos. La prioridad es construir tu fondo de emergencia."
          end
        when "debt_payoff"
          "Tienes deuda activa. Con el colchón inicial cubierto, la prioridad (paso 2) es liquidar la deuda antes de seguir creciendo el colchón."
        when "investing"
          "Sin deudas activas y con un colchón suficiente. La prioridad ahora es invertir y construir patrimonio."
        else
          "Fase derivada de tu situación financiera actual."
        end
      end

      # Total active recurring obligations — proxy for monthly essential spend.
      # Includes debt-linked obligations so the EF target covers debt payments too.
      def fetch_committed_monthly(account_id)
        ::RecurringObligation
          .where(account_id: account_id, active: true)
          .sum(:amount)
          .to_i
      end

      # Sum of current_amount across all savings goals whose name suggests an EF.
      def fetch_ef_balance(account_id)
        ::SavingsGoal
          .where(account_id: account_id)
          .select { |g| g.name.match?(/emergencia|emergency/i) }
          .sum { |g| g.current_amount.to_i }
      end

      def fetch_has_active_debts(account_id)
        ::Debt.where(account_id: account_id, status: :active).exists?
      end
    end
  end
end
