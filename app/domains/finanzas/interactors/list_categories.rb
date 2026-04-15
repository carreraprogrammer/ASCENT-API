module Finanzas
  module Interactors
    class ListCategories
      def initialize(repo: Finanzas::Repositories::CategoryRepository.new)
        @repo = repo
      end

      def call(account_id:)
        @repo.all_for_account(account_id)
      end
    end
  end
end
