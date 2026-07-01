module Finanzas
  module Interactors
    # Edita una subcategoría: su tier (category_id), nombre o ícono.
    # El tier es editable en cualquier subcategoría (función ⊥ tier, RFC-0001).
    # El destino debe ser una categoría de sistema (un tier real).
    class UpdateSubcategory
      def initialize(repo: Finanzas::Repositories::SubcategoryRepository.new)
        @repo = repo
      end

      def call(id:, category_id: nil, name: nil, icon: nil)
        record = @repo.find_record(id)
        raise Finanzas::Errors::InvalidSubcategory, "Subcategory not found" unless record

        if category_id.present?
          target = ::Category.find_by(id: category_id)
          raise Finanzas::Errors::InvalidSubcategory, "Category not found" unless target
          raise Finanzas::Errors::InvalidSubcategory, "Tier must be a system category" unless target.is_system?
        end

        @repo.update_fields(id, category_id: category_id, name: name, icon: icon)
      end
    end
  end
end
