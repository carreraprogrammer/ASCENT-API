module Finanzas
  module Interactors
    # Mantiene los totales estructurales del plan del mes ABIERTO en sincronía
    # con la realidad: recurring_obligations_total y debt_minimums_total se
    # recalculan desde los datos vivos cada vez que cambian recurrentes o deudas,
    # y al confirmar el plan.
    #
    # Semántica de snapshot: un plan cerrado (closed_at presente) nunca se toca —
    # su foto histórica es el registro. Solo el mes en curso es un documento vivo.
    #
    # Origen: bug del "presupuesto fantasma" (2026-06-12) — el plan congelaba en
    # la confirmación totales heredados del mes anterior y quedaba desactualizado
    # cuando el usuario agregaba obligaciones después.
    class RefreshPlanStructureTotals
      def initialize(
        recurring_repo: Finanzas::Repositories::RecurringObligationRepository.new,
        debt_repo: Finanzas::Repositories::DebtRepository.new
      )
        @recurring_repo = recurring_repo
        @debt_repo = debt_repo
      end

      # @return [Hash, nil] los totales aplicados, o nil si no hay plan abierto
      def call(account_id:, month: nil, year: nil)
        today = Date.today
        month ||= today.month
        year  ||= today.year

        plan = ::MonthlyFinancialPlan.find_by(account_id: account_id, month: month, year: year)
        return nil if plan.nil? || plan.closed_at.present?

        # Misma fórmula que GenerateMonthlyFinancialPlan: las obligaciones
        # vinculadas a deuda no entran en recurring (viven en debt_minimums).
        recurring_total = @recurring_repo.active_for_account(account_id)
                                         .reject { |o| o[:source_type] == "Debt" }
                                         .sum { |o| o[:amount].to_i }
        debt_minimums_total = @debt_repo.active_for_account(account_id)
                                        .sum { |d| d[:monthly_payment].to_i }

        return { unchanged: true } if plan.recurring_obligations_total == recurring_total &&
                                      plan.debt_minimums_total == debt_minimums_total

        plan.update_columns(
          recurring_obligations_total: recurring_total,
          debt_minimums_total: debt_minimums_total
        )
        { recurring_obligations_total: recurring_total, debt_minimums_total: debt_minimums_total }
      end
    end
  end
end
