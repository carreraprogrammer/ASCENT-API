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
        committed_monthly = fetch_committed_monthly(account_id)
        ef_balance        = fetch_ef_balance(account_id)
        has_active_debts  = fetch_has_active_debts(account_id)

        derive(committed_monthly, ef_balance, has_active_debts)
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
