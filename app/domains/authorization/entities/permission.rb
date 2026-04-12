module Authorization
  module Entities
    class Permission
      attr_reader :id, :resource, :action, :description
      def initialize(id:, resource:, action:, description: nil)
        @id = id
        @resource = resource
        @action = action
        @description = description
      end
      def slug
        "#{resource}:#{action}"
      end
    end
  end
end
