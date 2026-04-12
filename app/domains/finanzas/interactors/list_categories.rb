module Finanzas
  module Interactors
    class ListCategories
      def initialize(repo: Finanzas::Repositories::CategoryRepository.new)
        @repo = repo
      end

      def call(user_id:)
        @repo.all_for_user(user_id)
      end
    end
  end
end
