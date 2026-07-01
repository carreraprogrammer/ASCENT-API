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
            icon: sub.icon,
            is_system: sub.system?,
            category_id: sub.category_id,
            user_id: sub.user_id
          }
        }
      end

      # Recurso para la página de gestión: incluye el tier (category_type) y el conteo
      # de transacciones. `row` es el hash de SubcategoryRepository#manageable_for.
      def self.subcategory_management_resource(row)
        {
          id: row[:id].to_s,
          type: "subcategories",
          attributes: {
            name: row[:name],
            code: row[:code],
            icon: row[:icon],
            category_id: row[:category_id],
            category_type: row[:category_type],
            is_system: row[:is_system],
            user_id: row[:user_id],
            transaction_count: row[:transaction_count]
          }
        }
      end
    end
  end
end
