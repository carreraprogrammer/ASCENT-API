module Finanzas
  module Repositories
    # ASC-4: metas de ahorro y sus ajustes (retiros que no son movimientos de caja).
    class SavingsGoalRepository
      EMERGENCY_NAME = /emergencia|emergency/i

      def emergency_goals(account_id:)
        ::SavingsGoal.where(account_id: account_id).order(:id).select { |g| g.name.match?(EMERGENCY_NAME) }
                     .map { |g| map_goal(g) }
      end

      def adjustment_exists?(savings_goal_id:, key:)
        ::SavingsGoalAdjustment.exists?(savings_goal_id: savings_goal_id, key: key)
      end

      # Baja current_amount en `amount` (nunca por debajo de 0) y deja el ajuste registrado, todo o nada.
      def withdraw!(savings_goal_id:, account_id:, user_id:, amount:, date:, description:, key:)
        ::ActiveRecord::Base.transaction do
          goal = ::SavingsGoal.lock.find_by!(id: savings_goal_id, account_id: account_id)
          previous = goal.current_amount.to_i
          ::SavingsGoalAdjustment.create!(savings_goal: goal, account_id: account_id, user_id: user_id, date: date,
                                          amount: amount, previous_amount: previous, description: description, key: key)
          goal.update!(current_amount: [ previous - amount, 0 ].max)
          map_goal(goal)
        end
      end

      private

      def map_goal(goal)
        { id: goal.id, name: goal.name, current_amount: goal.current_amount.to_i, target_amount: goal.target_amount.to_i,
          user_id: goal.user_id }
      end
    end
  end
end
