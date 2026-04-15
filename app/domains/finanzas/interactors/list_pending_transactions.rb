module Finanzas
  module Interactors
    class ListPendingTransactions
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(account_id:, filters: {}, sort_by: "created_at", sort_dir: "asc")
        @repo.pending(account_id: account_id, filters: filters, sort_by: sort_by, sort_dir: sort_dir)
      end
    end
  end
end
