module Finanzas
  module Interactors
    # Borra una subcategoría propia del usuario, migrando todas sus transacciones
    # (y budgets/recurrentes/planned) a `reassign_to`. Las subcategorías de sistema
    # NO se borran (son la base sembrada; el seed las recrearía) — solo se edita su tier.
    class DestroySubcategory
      def initialize(repo: Finanzas::Repositories::SubcategoryRepository.new)
        @repo = repo
      end

      def call(id:, reassign_to: nil)
        record = @repo.find_record(id)
        raise Finanzas::Errors::InvalidSubcategory, "Subcategory not found" unless record
        raise Finanzas::Errors::InvalidSubcategory, "Las subcategorías de sistema no se pueden borrar (editá su tier)" if record.is_system?

        @repo.reassign_and_destroy(id, reassign_to: reassign_to)
      end
    end
  end
end
