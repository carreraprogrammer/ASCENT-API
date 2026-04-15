module Finanzas
  module Interactors
    class ListTransactions
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(account_id:, month:, year:, filters: {}, sort_by: "date", sort_dir: "desc", page: 1, per_page: 20)
        @repo.for_month(
          account_id: account_id,
          month: month,
          year: year,
          filters: filters,
          sort_by: sort_by,
          sort_dir: sort_dir,
          page: page,
          per_page: per_page
        )
      end
    end
  end
end
