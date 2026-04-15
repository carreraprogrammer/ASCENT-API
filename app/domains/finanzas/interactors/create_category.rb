module Finanzas
  module Interactors
    class CreateCategory
      def initialize(repo: Finanzas::Repositories::CategoryRepository.new)
        @repo = repo
      end

      def call(user_id:, account_id:, name:, code:, category_type:, color: nil, icon: nil)
        @repo.create(
          name: name,
          code: code,
          category_type: category_type,
          color: color,
          icon: icon,
          user_id: user_id,
          account_id: account_id
        )
      end
    end
  end
end
