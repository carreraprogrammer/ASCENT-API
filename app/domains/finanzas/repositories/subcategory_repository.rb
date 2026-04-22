module Finanzas
  module Repositories
    class SubcategoryRepository
      # Generates a URL-safe code from the given name, disambiguating with a
      # numeric suffix when a collision already exists in the same category.
      def generate_code(name, category_id:)
        base = name.to_s.downcase.strip
                    .gsub(/[áàäâ]/, "a").gsub(/[éèëê]/, "e")
                    .gsub(/[íìïî]/, "i").gsub(/[óòöô]/, "o")
                    .gsub(/[úùüû]/, "u").gsub(/ñ/, "n")
                    .gsub(/[^a-z0-9]+/, "_")
                    .gsub(/^_+|_+$/, "")
                    .presence || "subcategory"

        return base unless ::Subcategory.exists?(category_id: category_id, code: base)

        suffix = 2
        suffix += 1 while ::Subcategory.exists?(category_id: category_id, code: "#{base}_#{suffix}")
        "#{base}_#{suffix}"
      end

      def create(name:, category_id:, icon:, user_id:, is_system: false)
        code = generate_code(name, category_id: category_id)

        record = ::Subcategory.create!(
          name: name,
          code: code,
          category_id: category_id,
          icon: icon,
          user_id: user_id,
          is_system: is_system
        )
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidSubcategory, e.message
      end

      # Returns all subcategories for a given category, optionally scoped to a
      # user (system subcategories + that user's custom ones).
      def for_category(category_id:, user_id: nil)
        scope = ::Subcategory.where(category_id: category_id)
        scope = scope.where(is_system: true).or(
          ::Subcategory.where(category_id: category_id, user_id: user_id)
        ) if user_id.present?
        scope.map { |r| map_to_entity(r) }
      end

      private

      def map_to_entity(record)
        Finanzas::Entities::Subcategory.new(
          id: record.id,
          category_id: record.category_id,
          user_id: record.user_id,
          name: record.name,
          code: record.code,
          icon: record.icon,
          is_system: record.is_system,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end
    end
  end
end
