module Finanzas
  module Presenters
    class CategoryPresenter
      def self.collection(categories)
        {
          data: categories.map { |c| resource(c) }
        }
      end

      def self.single(category)
        { data: resource(category) }
      end

      def self.resource(category)
        {
          id: category.id.to_s,
          type: "categories",
          attributes: {
            name: category.name,
            code: category.code,
            category_type: category.category_type,
            color: category.color,
            icon: category.icon,
            is_system: category.system?,
            created_at: category.created_at,
            updated_at: category.updated_at
          },
          relationships: {
            subcategories: {
              data: category.subcategories.map { |s| subcategory_resource(s) }
            }
          }
        }
      end

      def self.subcategory_resource(sub)
        {
          id: sub.id.to_s,
          type: "subcategories",
          attributes: {
            name: sub.name,
            code: sub.code,
            is_system: sub.system?,
            category_id: sub.category_id
          }
        }
      end
    end
  end
end
