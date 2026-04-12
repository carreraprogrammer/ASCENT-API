module Authorization
  module Repositories
    class RoleRepository
      def find(id)
        map_to_entity(::Role.active.includes(:permissions).find(id))
      end
      def find_by_slug(slug)
        map_to_entity(::Role.active.includes(:permissions).find_by!(slug: slug))
      end
      def all
        ::Role.active.includes(:permissions).map { |r| map_to_entity(r) }
      end
      def create(name:, slug:, description: nil)
        map_to_entity(::Role.create!(name: name, slug: slug, description: description))
      end
      def update(id:, attrs:)
        record = ::Role.find(id)
        record.update!(attrs.slice(:name, :slug, :description, :active))
        map_to_entity(record)
      end
      def destroy(id)
        ::Role.find(id).destroy!
      end
      def assign_permission(role_id:, permission_id:)
        ::RolePermission.find_or_create_by!(role_id: role_id, permission_id: permission_id)
      end
      def revoke_permission(role_id:, permission_id:)
        ::RolePermission.find_by(role_id: role_id, permission_id: permission_id)&.destroy!
      end
      private
      def map_to_entity(record)
        permissions = record.permissions.map { |p| Authorization::Entities::Permission.new(id: p.id, resource: p.resource, action: p.action, description: p.description) }
        Authorization::Entities::Role.new(id: record.id, name: record.name, slug: record.slug, description: record.description, active: record.active, permissions: permissions)
      end
    end
  end
end
