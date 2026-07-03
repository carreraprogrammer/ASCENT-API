module Finanzas
  module Repositories
    class CategoryRepository
      def all_for_account(account_id)
        records = ::Category.where(account_id: account_id)
                             .or(::Category.where(user_id: nil))
                             .includes(:linked_subcategories, :subcategories)
                             .order(:category_type, :name)
        records.map { |r| map_to_entity(r) }
      end

      def find(id)
        record = ::Category.find_by(id: id)
        record && map_to_entity(record)
      end

      def create(name:, code:, category_type:, color: nil, icon: nil, user_id: nil, account_id: nil)
        record = ::Category.create!(
          name: name,
          code: code,
          category_type: category_type,
          color: color,
          icon: icon,
          user_id: user_id,
          account_id: account_id,
          is_system: false
        )
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidCategory, e.message
      end

      def destroy(id, account_id:)
        record = ::Category.find_by(id: id, account_id: account_id)
        raise Finanzas::Errors::CategoryNotFound, "Category #{id} not found" unless record
        raise Finanzas::Errors::CategoryNotDeletable, "System categories cannot be deleted" if record.is_system?
        record.destroy!
      end

      # Resuelve category_code / subcategory_code a IDs cuando el llamador
      # pasa códigos en lugar de IDs. Devuelve attrs limpio (sin los _code).
      def resolve_codes(attrs, account_id:)
        if attrs[:category_code] && !attrs[:category_id]
          record = ::Category.where(code: attrs[:category_code], account_id: account_id)
                             .or(::Category.where(code: attrs[:category_code], user_id: nil))
                             .first
          attrs[:category_id] = record&.id
        end

        if attrs[:subcategory_code] && !attrs[:subcategory_id]
          # RFC-0001 desacople: la subcategoría es una FUNCIÓN independiente del tier.
          # Se prefiere la que esté bajo la categoría dada (compat), y si no, cualquiera con
          # ese código (la función). NO se infiere el tier desde la subcategoría — el tier
          # (category_id) es independiente y lo fija quien clasifica.
          code = attrs[:subcategory_code]
          cid  = attrs[:category_id]
          subcat = (cid && ::Subcategory.find_by(code: code, category_id: cid)) ||
                   ::Subcategory.find_by(code: code)
          attrs[:subcategory_id] = subcat&.id
        end

        # Toda transacción necesita un TIER (category) para presupuestarse y aparecer en
        # el dashboard. Si no se pasó category explícita, se usa el tier primario de la
        # función como default (sobreescribible con category_code/category_id). Cubre
        # tanto el path por código como el que pasa subcategory_id directo. Sin esto la
        # transacción queda con category_id nil y no cuenta en el presupuesto.
        if attrs[:category_id].blank? && attrs[:subcategory_id].present?
          attrs[:category_id] = ::Subcategory.where(id: attrs[:subcategory_id]).pick(:category_id)
        end

        attrs.except(:category_code, :subcategory_code)
      end

      private

      def map_to_entity(record)
        # RFC-0001: las subcategorías (funciones) se vinculan por el m2m
        # category_subcategories; una función puede aparecer bajo varios tiers.
        # Fallback defensivo a la FK primaria si la categoría aún no tiene join
        # (subcategoría sin migrar). Evita categorías vacías en el wizard.
        linked = record.association(:linked_subcategories).loaded? ? record.linked_subcategories : []
        primary = record.association(:subcategories).loaded? ? record.subcategories : []
        subcategories = (linked.presence || primary).map do |s|
          Finanzas::Entities::Subcategory.new(
            id: s.id, category_id: s.category_id, user_id: s.user_id,
            name: s.name, code: s.code, icon: s.icon, is_system: s.is_system,
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
