module Authorization
  module Policies
    class UserPolicy < ApplicationPolicy
      def index? = has_permission?("users:read")
      def show? = has_permission?("users:read") || user.id == record.id
      def create? = has_permission?("users:create")
      def update? = has_permission?("users:update") || user.id == record.id
      def destroy? = has_permission?("users:destroy")
      def assign_role? = has_permission?("users:assign_role")
      def revoke_role? = has_permission?("users:revoke_role")
    end
  end
end
