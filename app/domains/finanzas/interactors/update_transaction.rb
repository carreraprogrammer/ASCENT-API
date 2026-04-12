module Finanzas
  module Interactors
    class UpdateTransaction
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(id:, user_id:, **attrs)
        transaction = @repo.find(id)
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless transaction
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless transaction.user_id == user_id

        permitted = attrs.slice(:status, :category_id, :subcategory_id, :concept,
                                :product, :amount, :date, :source, :metadata,
                                :clarification_resolved_at)

        if permitted[:amount] && permitted[:amount].to_i <= 0
          raise Finanzas::Errors::InvalidTransaction, "Amount must be positive"
        end

        @repo.update(id, permitted)
      end
    end
  end
end
