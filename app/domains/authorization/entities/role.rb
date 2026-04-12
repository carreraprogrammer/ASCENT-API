module Authorization
  module Entities
    class Role
      attr_reader :id, :name, :slug, :description, :active, :permissions
      def initialize(id:, name:, slug:, description: nil, active: true, permissions: [])
        @id = id
        @name = name
        @slug = slug
        @description = description
        @active = active
        @permissions = permissions
      end
    end
  end
end
