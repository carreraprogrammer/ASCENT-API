module Finanzas
  module Repositories
    class CategoryRepository
      def all_for_user(user_id)
        records = ::Category.where("user_id = ? OR user_id IS NULL", user_id)
                             .includes(:subcategories)
                             .order(:category_type, :name)
        records.map { |r| map_to_entity(r) }
      end

      def find(id)
        record = ::Category.find_by(id: id)
        record && map_to_entity(record)
      end

      def create(name:, code:, category_type:, color: nil, icon: nil, user_id: nil)
        record = ::Category.create!(
          name: name,
          code: code,
          category_type: category_type,
          color: color,
          icon: icon,
          user_id: user_id,
          is_system: false
        )
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidCategory, e.message
      end

      def destroy(id)
        record = ::Category.find_by(id: id)
        raise Finanzas::Errors::CategoryNotFound, "Category #{id} not found" unless record
        raise Finanzas::Errors::CategoryNotDeletable, "System categories cannot be deleted" if record.is_system?
        record.destroy!
      end

      private

      def map_to_entity(record)
        subcategories = (record.association(:subcategories).loaded? ? record.subcategories : []).map do |s|
          Finanzas::Entities::Subcategory.new(
            id: s.id, category_id: s.category_id, name: s.name,
            code: s.code, is_system: s.is_system,
            created_at: s.created_at, updated_at: s.updated_at
          )
        end

        Finanzas::Entities::Category.new(
          id: record.id, user_id: record.user_id, name: record.name,
          code: record.code, category_type: record.category_type,
          color: record.color, icon: record.icon, is_system: record.is_system,
          created_at: record.created_at, updated_at: record.updated_at,
          subcategories: subcategories
        )
      end
    end
  end
end
