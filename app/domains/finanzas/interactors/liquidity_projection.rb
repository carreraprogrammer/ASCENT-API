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
      # @param plan                  [Hash, nil]    plan mensual vigente (puede ser nil)
      # @param balance               [Hash]         balance del período {income_confirmed:, expense_confirmed:, ...}
      # @param income_sources        [Array<Hash>]  fuentes de ingreso activas de la cuenta (opcional)
      # @param realized_income_by_source [Hash]     ingresos confirmados agrupados por income_source_id
      # @param credit_card_pending   [Integer]      total de compras con tarjeta de crédito sin pagar al banco
      # @param today                 [Date, nil]    fecha actual (opcional, por defecto Date.today)
      # @return                      [Hash, nil]    proyección de liquidez, o nil si no hay plan
      def call(plan:, balance:, income_sources: [], realized_income_by_source: {}, credit_card_pending: 0, today: nil)
        return nil unless plan

        confirmed_balance = balance[:income_confirmed].to_i - balance[:expense_confirmed].to_i

        # Ingreso variable pendiente: suma de fuentes activas de clasificación variable
        # cuya ventana siga vigente y que todavía no se hayan materializado
        # como transacciones enlazadas a la fuente proyectada.
        today_day = (today || Date.today).day
        pending_income = pending_variable_income(income_sources, realized_income_by_source, today_day)

        # Obligaciones del próximo ciclo: recurrentes + mínimos de deuda + crédito pendiente.
        # El crédito pendiente es lo que se le debe al banco por compras aún no pagadas.
        next_cycle_obligations = plan[:recurring_obligations_total].to_i +
                                 plan[:debt_minimums_total].to_i +
                                 credit_card_pending.to_i

        protected_buffer       = plan[:protected_buffer_amount].to_i

        projected_eom_balance  = confirmed_balance + pending_income
        free_after_obligations = projected_eom_balance - next_cycle_obligations
        safe_to_deploy         = [ free_after_obligations - protected_buffer, 0 ].max

        {
          confirmed_balance:      confirmed_balance,
          pending_income:         pending_income,
          projected_eom_balance:  projected_eom_balance,
          next_cycle_obligations: next_cycle_obligations,
          credit_card_pending:    credit_card_pending.to_i,
          protected_buffer:       protected_buffer,
          free_after_obligations: free_after_obligations,
          safe_to_deploy:         safe_to_deploy,
          buffer_status:          classify_status(free_after_obligations, protected_buffer)
        }
      end

      private

      # Suma el saldo pendiente de fuentes variables activas cuya ventana de pago
      # aún no cerró. Si una transacción real ya quedó vinculada a la fuente, se
      # descuenta para evitar duplicar "proyectado" + "realizado".
      #
      # Una fuente es "variable" si su classification es 'variable' O su flag is_variable
      # es true (ambos campos existen en el modelo; el criterio es OR para cubrir ambas
      # convenciones de datos).
      def pending_variable_income(income_sources, realized_income_by_source, today_day)
        Array(income_sources)
          .select { |src| src[:active] && variable_source?(src) && src[:expected_day_to].to_i >= today_day }
          .sum do |src|
            expected = src[:expected_amount].to_i
            realized = realized_income_by_source.fetch(src[:id], realized_income_by_source[src[:id].to_s]).to_i
            [expected - realized, 0].max
          end
      end

      def variable_source?(src)
        src[:classification] == "variable" || src[:is_variable] == true
      end

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
