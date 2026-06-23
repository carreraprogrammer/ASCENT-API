module Finanzas
  module Interactors
    class RegisterDebtPayment
      def initialize(transaction_creator: Finanzas::Interactors::CreateTransaction.new)
        @transaction_creator = transaction_creator
      end

      def call(user_id:, account_id:, debt_id:, date:, amount:, concept: nil,
               product: nil, category_id: nil, subcategory_id: nil, source: "manual",
               status: "confirmed", metadata: {}, payment_source: "debit",
               recurring_obligation_id: nil)
          amount = amount.to_i
          raise Finanzas::Errors::InvalidTransaction, "Amount must be positive" if amount <= 0
          raise Finanzas::Errors::InvalidTransaction, "Debt payments must be confirmed" unless status == "confirmed"

        ActiveRecord::Base.transaction do
          debt = ::Debt.lock.where(id: debt_id, account_id: account_id).first
          raise ActiveRecord::RecordNotFound, "Debt #{debt_id} not found" unless debt

          recurring_obligation = resolve_recurring_obligation(
            account_id: account_id,
            debt_id: debt.id,
            recurring_obligation_id: recurring_obligation_id
          )
          previous_balance = debt.current_balance.to_i
          new_balance = [ previous_balance - amount, 0 ].max

          transaction = @transaction_creator.call(
            user_id: user_id,
            account_id: account_id,
            date: date,
            concept: concept.presence || "Abono a #{debt.name}",
            product: product,
            amount: amount,
            transaction_type: "expense",
            category_id: category_id,
            subcategory_id: subcategory_id,
            source: source,
            status: status,
            metadata: payment_metadata(metadata, debt, recurring_obligation, previous_balance, new_balance),
            payment_source: payment_source,
            debt_id: debt.id,
            recurring_obligation_id: recurring_obligation&.id,
            skip_debt_balance: true
          )

          debt.update!(current_balance: new_balance)
          {
            transaction: transaction,
            debt: debt_payload(debt),
            previous_balance: previous_balance,
            current_balance: debt.current_balance,
            applied_amount: amount
          }
        end
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def resolve_recurring_obligation(account_id:, debt_id:, recurring_obligation_id:)
        scope = ::RecurringObligation.where(account_id: account_id, source_type: "Debt", source_id: debt_id)
        return scope.find_by(id: recurring_obligation_id) if recurring_obligation_id.present?

        scope.find_by(active: true)
      end

      def payment_metadata(metadata, debt, recurring_obligation, previous_balance, new_balance)
        (metadata || {}).to_h.stringify_keys.merge(
          "debt_payment" => true,
          "debt_id" => debt.id,
          "debt_name" => debt.name,
          "recurring_obligation_id" => recurring_obligation&.id,
          "previous_debt_balance" => previous_balance,
          "new_debt_balance" => new_balance
        ).compact
      end

      def debt_payload(debt)
        {
          id: debt.id,
          name: debt.name,
          current_balance: debt.current_balance,
          status: debt.status,
          monthly_payment: debt.monthly_payment
        }
      end
    end
  end
end
