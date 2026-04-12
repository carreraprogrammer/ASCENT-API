module Forms
  module Interactors
    class FetchAllFormSchemas
      def initialize(repo: Forms::Repositories::FormSchemaRepository.new)
        @repo = repo
      end
      def call
        @repo.all_active
      end
    end
  end
end
