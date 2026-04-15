module Finanzas
  module Interactors
    class DestroyTransaction
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(id:, account_id:)
        transaction = @repo.find(id, account_id: account_id)
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless transaction

        @repo.destroy(id, account_id: account_id)
      end
    end
  end
end
