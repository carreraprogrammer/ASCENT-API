module Finanzas
  module Interactors
    # Proyección de liquidez hacia adelante.
    #
    # Responde la pregunta real: después de cubrir todas las obligaciones del
    # próximo ciclo (inicio de mes siguiente), ¿cuánto queda libre para mover?
    #
    # No hace queries — opera sobre los hashes que el SummaryController ya cargó.
    # Todos los valores son enteros en COP.
    class LiquidityProjection
      # @param plan    [Hash, nil]  plan mensual vigente (puede ser nil)
      # @param balance [Hash]       balance del período {income_confirmed:, expense_confirmed:, ...}
      # @return        [Hash, nil]  proyección de liquidez, o nil si no hay plan
      def call(plan:, balance:)
        return nil unless plan

        confirmed_balance      = balance[:income_confirmed].to_i - balance[:expense_confirmed].to_i
        total_planned_income   = plan[:base_budget_income].to_i + plan[:expected_variable_income].to_i
        income_confirmed       = balance[:income_confirmed].to_i

        # Ingreso que aún no ha llegado este mes (0 si ya llegó todo o más)
        pending_income         = [ total_planned_income - income_confirmed, 0 ].max

        # Obligaciones que se van a ejecutar al inicio del próximo ciclo:
        # recurring_obligations_total ya excluye mínimos de deuda (son cuentas separadas en el plan)
        next_cycle_obligations = plan[:recurring_obligations_total].to_i +
                                 plan[:debt_minimums_total].to_i

        protected_buffer       = plan[:protected_buffer_amount].to_i

        projected_eom_balance  = confirmed_balance + pending_income
        free_after_obligations = projected_eom_balance - next_cycle_obligations
        safe_to_deploy         = [ free_after_obligations - protected_buffer, 0 ].max

        {
          confirmed_balance:      confirmed_balance,
          pending_income:         pending_income,
          projected_eom_balance:  projected_eom_balance,
          next_cycle_obligations: next_cycle_obligations,
          protected_buffer:       protected_buffer,
          free_after_obligations: free_after_obligations,
          safe_to_deploy:         safe_to_deploy,
          buffer_status:          classify_status(free_after_obligations, protected_buffer)
        }
      end

      private

      def classify_status(free_after_obligations, protected_buffer)
        if free_after_obligations <= 0
          "critical"
        elsif free_after_obligations <= protected_buffer
          "tight"
        else
          "comfortable"
        end
      end
    end
  end
end
