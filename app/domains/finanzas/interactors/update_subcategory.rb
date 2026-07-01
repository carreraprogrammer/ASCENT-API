module Finanzas
  module Interactors
    # Edita una subcategoría: sus vínculos a categorías (una o más tiers), nombre o ícono.
    # Los vínculos son editables en cualquier subcategoría (función ⊥ tier, RFC-0001).
    # Todos los tiers deben ser categorías de sistema.
    class UpdateSubcategory
      def initialize(repo: Finanzas::Repositories::SubcategoryRepository.new)
        @repo = repo
      end

      def call(id:, category_ids: nil, name: nil, icon: nil, description: nil)
        record = @repo.find_record(id)
        raise Finanzas::Errors::InvalidSubcategory, "Subcategory not found" unless record

        if category_ids.present?
          ids = Array(category_ids).map(&:to_i).uniq
          categories = ::Category.where(id: ids)
          raise Finanzas::Errors::InvalidSubcategory, "Category not found" unless categories.count == ids.size
          raise Finanzas::Errors::InvalidSubcategory, "Tier must be a system category" unless categories.all?(&:is_system?)
        end

        @repo.update_fields(id, category_ids: category_ids, name: name, icon: icon, description: description)
      end
    end
  end
end
