module Forms
  module Interactors
    class CreateFormSchema
      def initialize(repo: Forms::Repositories::FormSchemaRepository.new)
        @repo = repo
      end
      def call(attrs)
        schema = Forms::Entities::FormSchema.new(attrs)
        raise Forms::Errors::InvalidSchema, schema.errors.join(", ") unless schema.valid?
        @repo.create(attrs)
      end
    end
  end
end
