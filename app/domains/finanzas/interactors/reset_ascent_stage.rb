module Finanzas
  module Interactors
    # ASC-4 fase 0: reinicia "Tu ascenso" en el Fondo semilla. El progreso del Fondo semilla y del fondo de
    # emergencia sale de current_amount de las metas cuyo nombre dice emergencia (DerivePhase, Dashboard), así
    # que el reinicio es un ajuste de esas metas hasta 0, con fecha y descripción, sin tocar movimientos.
    # Idempotente: el ajuste lleva la clave "reset_stage:<fecha>" y una segunda corrida no hace nada. El monto
    # es lo que falte para llegar a 0, así que nada se descuenta dos veces.
    class ResetAscentStage
      DESCRIPTION = "Fondo semilla usado — reinicio del ascenso".freeze

      def initialize(goal_repo: Finanzas::Repositories::SavingsGoalRepository.new)
        @goal_repo = goal_repo
      end

      def call(account_id:, user_id:, date: Date.current, description: DESCRIPTION)
        key = "reset_stage:#{date.iso8601}"
        result = { goals: 0, adjusted: 0, already_done: 0, already_zero: 0, total_adjusted: 0 }
        @goal_repo.emergency_goals(account_id: account_id).each do |goal|
          result[:goals] += 1
          if @goal_repo.adjustment_exists?(savings_goal_id: goal[:id], key: key)
            result[:already_done] += 1
          elsif goal[:current_amount] <= 0
            result[:already_zero] += 1
          else
            @goal_repo.withdraw!(savings_goal_id: goal[:id], account_id: account_id, user_id: user_id,
                                 amount: goal[:current_amount], date: date, description: description, key: key)
            result[:adjusted] += 1
            result[:total_adjusted] += goal[:current_amount]
          end
        end
        result
      end
    end
  end
end
