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
      # con su tier (category_type) y el conteo de transacciones de la cuenta.
      def manageable_for(account_id:, user_id:)
        counts = ::Transaction.where(account_id: account_id)
                              .where.not(subcategory_id: nil)
                              .group(:subcategory_id).count
        ::Subcategory.includes(:category)
                     .where(is_system: true)
                     .or(::Subcategory.where(user_id: user_id))
                     .order(:name)
                     .map do |r|
          {
            id: r.id, name: r.name, code: r.code, icon: r.icon,
            category_id: r.category_id, category_type: r.category&.category_type,
            is_system: r.is_system, user_id: r.user_id,
            transaction_count: counts[r.id].to_i
          }
        end
      end

      def find_record(id)
        ::Subcategory.find_by(id: id)
      end

      def update_fields(id, category_id: nil, name: nil, icon: nil)
        record = ::Subcategory.find_by(id: id)
        raise Finanzas::Errors::InvalidSubcategory, "Subcategory not found" unless record

        record.category_id = category_id if category_id.present?
        record.name = name if name.present?
        record.icon = icon if icon.present?
        record.save!
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
          is_system: record.is_system,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end
    end
  end
end
