module Finanzas
  module Interactors
    class CreateSubcategory
      def initialize(repo: Finanzas::Repositories::SubcategoryRepository.new)
        @repo = repo
      end

      def call(name:, category_id:, icon:, user_id:)
        raise Finanzas::Errors::InvalidSubcategory, "Name is required" if name.blank?
        raise Finanzas::Errors::InvalidSubcategory, "Icon is required" if icon.blank?

        category = ::Category.find_by(id: category_id)
        raise Finanzas::Errors::InvalidSubcategory, "Category not found" unless category
        raise Finanzas::Errors::InvalidSubcategory, "Only system categories can have user subcategories" unless category.is_system?

        @repo.create(
          name: name,
          category_id: category_id,
          icon: icon,
          user_id: user_id,
          is_system: false
        )
      end
    end
  end
end
