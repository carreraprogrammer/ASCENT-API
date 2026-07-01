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

      # Subcategorías gestionables por la cuenta (de sistema + propias del usuario),
      # con las CATEGORÍAS a las que están vinculadas (para los chips) y el conteo de txns.
      def manageable_for(account_id:, user_id:)
        counts = ::Transaction.where(account_id: account_id)
                              .where.not(subcategory_id: nil)
                              .group(:subcategory_id).count
        ::Subcategory.includes(:linked_categories, :category)
                     .where(is_system: true)
                     .or(::Subcategory.where(user_id: user_id))
                     .order(:name)
                     .map do |r|
          cats = r.linked_categories.presence || [ r.category ].compact
          {
            id: r.id, name: r.name, code: r.code, icon: r.icon, description: r.description,
            is_system: r.is_system, user_id: r.user_id,
            transaction_count: counts[r.id].to_i,
            categories: cats.map { |c| { id: c.id, category_type: c.category_type, color: c.color } }
          }
        end
      end

      def find_record(id)
        ::Subcategory.find_by(id: id)
      end

      # Crea una subcategoría vinculada a una o más categorías (la primera = tier primario).
      def create_with_links(name:, category_ids:, icon:, user_id:, description: nil, is_system: false)
        ids = Array(category_ids).map(&:to_i).uniq
        raise Finanzas::Errors::InvalidSubcategory, "At least one category is required" if ids.empty?

        primary = ids.first
        code = generate_code(name, category_id: primary)
        ActiveRecord::Base.transaction do
          record = ::Subcategory.create!(
            name: name, code: code, category_id: primary,
            icon: icon, description: description, user_id: user_id, is_system: is_system
          )
          ids.each { |cid| ::CategorySubcategory.create!(subcategory_id: record.id, category_id: cid) }
          map_to_entity(record)
        end
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidSubcategory, e.message
      end

      # Actualiza los vínculos (many-to-many) y/o nombre/ícono. Si se pasan category_ids,
      # reemplaza el set de vínculos y fija el primario = primero.
      def update_fields(id, category_ids: nil, name: nil, icon: nil, description: nil)
        record = ::Subcategory.find_by(id: id)
        raise Finanzas::Errors::InvalidSubcategory, "Subcategory not found" unless record

        ActiveRecord::Base.transaction do
          if category_ids.present?
            ids = Array(category_ids).map(&:to_i).uniq
            record.category_subcategories.where.not(category_id: ids).destroy_all
            existing = record.category_subcategories.pluck(:category_id)
            (ids - existing).each { |cid| ::CategorySubcategory.create!(subcategory_id: record.id, category_id: cid) }
            record.category_id = ids.first
          end
          record.name = name if name.present?
          record.icon = icon if icon.present?
          record.description = description unless description.nil?
          record.save!
        end
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidSubcategory, e.message
      end

      # Reasigna todas las referencias (transacciones, budgets, recurrentes, planned)
      # a `reassign_to` y luego borra la subcategoría. Atómico: sin huérfanos.
      def reassign_and_destroy(id, reassign_to:)
        record = ::Subcategory.find_by(id: id)
        raise Finanzas::Errors::InvalidSubcategory, "Subcategory not found" unless record

        target = reassign_to.present? ? ::Subcategory.find_by(id: reassign_to) : nil
        raise Finanzas::Errors::InvalidSubcategory, "Target subcategory not found" if reassign_to.present? && target.nil?
        raise Finanzas::Errors::InvalidSubcategory, "Cannot reassign to itself" if target && target.id == record.id

        ActiveRecord::Base.transaction do
          if target
            ::Transaction.where(subcategory_id: id).update_all(subcategory_id: target.id)
            ::Budget.where(subcategory_id: id).update_all(subcategory_id: target.id)
            ::RecurringObligation.where(subcategory_id: id).update_all(subcategory_id: target.id)
            ::PlannedExpense.where(subcategory_id: id).update_all(subcategory_id: target.id)
          end
          record.destroy!
        end
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
          description: record.description,
          is_system: record.is_system,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end
    end
  end
end
