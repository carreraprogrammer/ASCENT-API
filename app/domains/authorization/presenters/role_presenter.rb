module Authorization
  module Presenters
    class RolePresenter
      def self.single(entity)
        { data: { id: entity.id.to_s, type: "roles", attributes: { name: entity.name, slug: entity.slug, description: entity.description, active: entity.active, permissions: entity.permissions.map(&:slug) } } }
      end
      def self.collection(entities)
        { data: entities.map { |e| single(e)[:data] }, meta: { total: entities.size } }
      end
    end
  end
end
