module Finanzas
  module Interactors
    # Crea una subcategoría (función) vinculada a UNA O MÁS categorías (tiers).
    # La primera categoría es el tier primario/default. Todas deben ser de sistema.
    class CreateSubcategory
      def initialize(repo: Finanzas::Repositories::SubcategoryRepository.new)
        @repo = repo
      end

      def call(name:, category_ids:, icon:, user_id:, description: nil)
        raise Finanzas::Errors::InvalidSubcategory, "Name is required" if name.blank?
        raise Finanzas::Errors::InvalidSubcategory, "Icon is required" if icon.blank?

        ids = Array(category_ids).map(&:to_i).uniq
        raise Finanzas::Errors::InvalidSubcategory, "At least one category is required" if ids.empty?
        validate_system_categories!(ids)

        @repo.create_with_links(
          name: name, category_ids: ids, icon: icon, description: description, user_id: user_id, is_system: false
        )
      end

      private

      def validate_system_categories!(ids)
        categories = ::Category.where(id: ids)
        raise Finanzas::Errors::InvalidSubcategory, "Category not found" unless categories.count == ids.size
        raise Finanzas::Errors::InvalidSubcategory, "Only system categories can hold subcategories" unless categories.all?(&:is_system?)
      end
    end
  end
end
