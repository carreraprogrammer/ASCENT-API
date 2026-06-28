module Finanzas
  module Interactors
    # Deterministically derives the user's financial phase using Ramsey Baby Steps order.
    # Never reads FinancialContext.phase — derives from real financial data.
    #
    # Order:
    #   Step 1: 1-month emergency fund
    #   Step 2: Debt snowball (all active debts cleared)
    #   Step 3: 3-month emergency fund
    #   Step 4+: investing
    class DerivePhase
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
        if committed_monthly > 0
          # Step 1: 1-month emergency fund not yet reached
          return "emergency_fund" if ef_balance < committed_monthly
        end

        # Step 2: clear all debts before growing the EF further
        return "debt_payoff" if has_active_debts

        if committed_monthly > 0
          # Step 3: grow emergency fund to 3 months
          return "emergency_fund" if ef_balance < 3 * committed_monthly
        end

        "investing"
      end

      # Razón legible (secuencia Ramsey) — el "por qué" de la fase deducida.
      def reason_for(phase, committed_monthly, ef_balance, has_active_debts)
        case phase
        when "emergency_fund"
          if committed_monthly.positive? && ef_balance < committed_monthly
            "Tu colchón aún no cubre 1 mes de gastos fijos. La prioridad (paso 1) es un fondo de emergencia inicial antes de atacar la deuda."
          else
            "Ya no tienes deudas activas, pero tu colchón aún no llega a 3 meses de gastos fijos. La prioridad (paso 3) es completar el fondo de emergencia."
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
