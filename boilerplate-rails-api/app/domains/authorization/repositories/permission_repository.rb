module Authorization
  module Repositories
    class PermissionRepository
      def all
        ::Permission.all.map { |p| map_to_entity(p) }
      end
      def find(id)
        map_to_entity(::Permission.find(id))
      end
      def find_by_slug(slug)
        resource, action = slug.split(":")
        map_to_entity(::Permission.find_by!(resource: resource, action: action))
      end
      def create(resource:, action:, description: nil)
        map_to_entity(::Permission.create!(resource: resource, action: action, description: description))
      end
      private
      def map_to_entity(record)
        Authorization::Entities::Permission.new(id: record.id, resource: record.resource, action: record.action, description: record.description)
      end
    end
  end
end
