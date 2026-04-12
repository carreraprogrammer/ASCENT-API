module Finanzas
  module Interactors
    class DestroyTransaction
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(id:, user_id:)
        transaction = @repo.find(id)
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless transaction
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless transaction.user_id == user_id

        @repo.destroy(id)
      end
    end
  end
end
