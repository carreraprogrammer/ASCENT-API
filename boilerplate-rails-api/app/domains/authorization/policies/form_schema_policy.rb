module Authorization
  module Policies
    class FormSchemaPolicy < ApplicationPolicy
      def create? = has_permission?("form_schemas:create")
      def update? = has_permission?("form_schemas:update")
      def destroy? = has_permission?("form_schemas:destroy")
    end
  end
end
