module Finanzas
  module Interactors
    class ListTransactions
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(account_id:, month:, year:)
        @repo.for_month(account_id: account_id, month: month, year: year)
      end
    end
  end
end
