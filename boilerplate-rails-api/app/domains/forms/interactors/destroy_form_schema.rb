module Forms
  module Interactors
    class DestroyFormSchema
      def initialize(repo: Forms::Repositories::FormSchemaRepository.new)
        @repo = repo
      end

      def call(slug:)
        @repo.deactivate(slug)
      end
    end
  end
end
