module Finanzas
  module Interactors
    class ListTransactions
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(user_id:, month:, year:)
        @repo.for_month(user_id: user_id, month: month, year: year)
      end
    end
  end
end
