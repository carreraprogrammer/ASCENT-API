module Finanzas
  module Interactors
    class DestroyCategory
      def initialize(repo: Finanzas::Repositories::CategoryRepository.new)
        @repo = repo
      end

      def call(id:, account_id: nil)
        @repo.destroy(id, account_id: account_id)
      end
    end
  end
end
