module Finanzas
  module Errors
    class CategoryNotFound < StandardError; end
    class CategoryNotDeletable < StandardError; end
    class TransactionNotFound < StandardError; end
    class InvalidTransaction < StandardError; end
    class InvalidCategory < StandardError; end
    class InvalidSubcategory < StandardError; end
    class SubcategoryNotFound < StandardError; end
    class InvalidBudgetLine < StandardError; end
    class DuplicateTransaction < StandardError
      attr_reader :existing_id
      def initialize(msg = nil, existing_id: nil)
        @existing_id = existing_id
        super(msg)
      end
    end
  end
end
