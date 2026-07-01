module Finanzas
  module Interactors
    # Lista las subcategorías gestionables por la cuenta (de sistema + propias),
    # con su tier (category_type) y el conteo de transacciones. Para la página de
    # gestión de subcategorías en Transacciones.
    class ListSubcategories
      def initialize(repo: Finanzas::Repositories::SubcategoryRepository.new)
        @repo = repo
      end

      def call(account_id:, user_id:)
        @repo.manageable_for(account_id: account_id, user_id: user_id)
      end
    end
  end
end
