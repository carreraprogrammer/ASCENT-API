module Finanzas
  module Errors
    class CategoryNotFound < StandardError; end
    class CategoryNotDeletable < StandardError; end
    class TransactionNotFound < StandardError; end
    class InvalidTransaction < StandardError; end
    class InvalidCategory < StandardError; end
  end
end
