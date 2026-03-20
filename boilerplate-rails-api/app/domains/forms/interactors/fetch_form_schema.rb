module Forms
  module Interactors
    class FetchFormSchema
      def initialize(repo: Forms::Repositories::FormSchemaRepository.new)
        @repo = repo
      end
      def call(slug:)
        schema = @repo.find_by_slug(slug)
        raise ActiveRecord::RecordNotFound, "Form schema '#{slug}' not found" if schema.nil?
        schema
      end
    end
  end
end
