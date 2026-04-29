module Finanzas
  module Interactors
    # Proyección de liquidez hacia el próximo ciclo.
    #
    # Responde la pregunta real: después de cubrir todas las obligaciones del
    # próximo ciclo, ¿cuánto queda libre para mover?
    #
    # La proyección suma tres componentes de ingreso pendiente:
    #   1. pending_variable  — ingreso variable cuya ventana este mes aún no cerró
    #   2. pending_base      — ingreso base cuya ventana este mes aún no cerró (ej: llegó tarde)
    #   3. next_cycle_base   — ingreso base cuya ventana ya cerró este mes y llegará en el próximo ciclo
    #
    # El componente (3) es el crítico: evita falsos "critical" a fin de mes cuando el saldo
    # es bajo pero el ingreso fijo del próximo mes está a días de llegar.
    #
    # No hace queries — opera sobre los hashes que el SummaryController ya cargó.
    # Todos los valores son enteros en COP.
    class LiquidityProjection
      # @param plan                      [Hash, nil]    plan mensual vigente (puede ser nil)
      # @param balance                   [Hash]         {income_confirmed:, expense_confirmed:, ...}
      # @param income_sources            [Array<Hash>]  fuentes de ingreso activas de la cuenta
      # @param realized_income_by_source [Hash]         ingresos confirmados agrupados por income_source_id
      # @param credit_card_pending       [Integer]      total de compras TC sin pagar al banco
      # @param today                     [Date, nil]    fecha actual (por defecto Date.today)
      # @return                          [Hash, nil]    proyección, o nil si no hay plan
      def call(plan:, balance:, income_sources: [], realized_income_by_source: {}, credit_card_pending: 0, today: nil)
        return nil unless plan

        today_day = (today || Date.today).day
        confirmed_balance = balance[:income_confirmed].to_i - balance[:expense_confirmed].to_i

        pending_variable = pending_variable_income(income_sources, realized_income_by_source, today_day)
        pending_base     = pending_base_income(income_sources, realized_income_by_source, today_day)
        next_cycle_base  = next_cycle_base_income(income_sources, today_day)

        pending_income = pending_variable + pending_base + next_cycle_base

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
          pending_variable:       pending_variable,
          pending_base:           pending_base,
          next_cycle_base:        next_cycle_base,
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

      # Ingreso variable cuya ventana este mes aún no cerró y no se materializó todavía.
      def pending_variable_income(income_sources, realized_income_by_source, today_day)
        Array(income_sources)
          .select { |src| src[:active] && variable_source?(src) && src[:expected_day_to].to_i >= today_day }
          .sum do |src|
            expected = src[:expected_amount].to_i
            realized = fetch_realized(realized_income_by_source, src[:id])
            [ expected - realized, 0 ].max
          end
      end

      # Ingreso base cuya ventana este mes aún no cerró y no ha llegado todavía.
      # Cubre el caso de inicio de mes donde el ingreso base todavía está en camino.
      def pending_base_income(income_sources, realized_income_by_source, today_day)
        Array(income_sources)
          .select { |src| src[:active] && !variable_source?(src) && src[:expected_day_to].to_i >= today_day }
          .sum do |src|
            expected = src[:expected_amount].to_i
            realized = fetch_realized(realized_income_by_source, src[:id])
            [ expected - realized, 0 ].max
          end
      end

      # Ingreso base cuya ventana este mes ya cerró — llegará de nuevo en el próximo ciclo.
      # Sin deducción de realizados: la instancia del próximo ciclo aún no llegó.
      # Este componente evita los falsos "critical" de fin de mes.
      def next_cycle_base_income(income_sources, today_day)
        Array(income_sources)
          .select { |src| src[:active] && !variable_source?(src) && src[:expected_day_to].to_i < today_day }
          .sum { |src| src[:expected_amount].to_i }
      end

      def variable_source?(src)
        src[:classification] == "variable" || src[:is_variable] == true
      end

      def fetch_realized(realized_income_by_source, id)
        realized_income_by_source.fetch(id, realized_income_by_source[id.to_s]).to_i
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
