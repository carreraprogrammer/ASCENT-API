module Finanzas
  module Interactors
    class ListPendingTransactions
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(account_id:)
        @repo.pending(account_id: account_id)
      end
    end
  end
end
