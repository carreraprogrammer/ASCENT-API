module Finanzas
  module Interactors
    # Registra un aporte a una meta (SavingsGoal) como transacción vinculada.
    # El incremento de current_amount lo aplica el auto-balance del repository
    # (vía savings_goal_id), igual que un aporte a un bolsillo. Paralelo a
    # RegisterDebtPayment, pero sin tocar el balance a mano.
    class RegisterGoalContribution
      def initialize(transaction_creator: Finanzas::Interactors::CreateTransaction.new)
        @transaction_creator = transaction_creator
      end

      def call(user_id:, account_id:, savings_goal_id:, date:, amount:, concept: nil,
               product: nil, category_id: nil, subcategory_id: nil, source: "manual",
               status: "confirmed", metadata: {}, payment_source: "debit")
        amount = amount.to_i
        raise Finanzas::Errors::InvalidTransaction, "Amount must be positive" if amount <= 0
        raise Finanzas::Errors::InvalidTransaction, "Goal contributions must be confirmed" unless status == "confirmed"

        goal = ::SavingsGoal.find_by(id: savings_goal_id, account_id: account_id)
        raise ActiveRecord::RecordNotFound, "Savings goal #{savings_goal_id} not found" unless goal

        previous_amount = goal.current_amount.to_i

        transaction = @transaction_creator.call(
          user_id: user_id,
          account_id: account_id,
          date: date,
          concept: concept.presence || "Aporte a #{goal.name}",
          product: product,
          amount: amount,
          transaction_type: "expense",
          category_id: category_id,
          subcategory_id: subcategory_id,
          source: source,
          status: status,
          metadata: contribution_metadata(metadata, goal, previous_amount),
          payment_source: payment_source,
          savings_goal_id: goal.id
        )

        goal.reload
        {
          transaction: transaction,
          goal: goal_payload(goal),
          previous_amount: previous_amount,
          current_amount: goal.current_amount,
          applied_amount: amount
        }
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def contribution_metadata(metadata, goal, previous_amount)
        (metadata || {}).to_h.stringify_keys.merge(
          "goal_contribution" => true,
          "savings_goal_id" => goal.id,
          "savings_goal_name" => goal.name,
          "previous_goal_amount" => previous_amount
        ).compact
      end

      def goal_payload(goal)
        {
          id: goal.id,
          name: goal.name,
          current_amount: goal.current_amount,
          target_amount: goal.target_amount,
          status: goal.status
        }
      end
    end
  end
end
