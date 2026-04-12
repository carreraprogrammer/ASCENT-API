module Authorization
  module Policies
    class RolePolicy < ApplicationPolicy
      def index? = has_permission?("roles:read")
      def show? = has_permission?("roles:read")
      def create? = has_permission?("roles:create")
      def update? = has_permission?("roles:update")
      def destroy? = has_permission?("roles:destroy")
      def assign_permission? = update?
      def revoke_permission? = update?
    end
  end
end
