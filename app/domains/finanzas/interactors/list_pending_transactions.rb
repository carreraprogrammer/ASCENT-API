module Finanzas
  module Interactors
    class ListPendingTransactions
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(user_id:)
        @repo.pending(user_id: user_id)
      end
    end
  end
end
