module Finanzas
  module Interactors
    class DestroyCategory
      def initialize(repo: Finanzas::Repositories::CategoryRepository.new)
        @repo = repo
      end

      def call(id:)
        @repo.destroy(id)
      end
    end
  end
end
