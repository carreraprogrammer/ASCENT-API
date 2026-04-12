module Authorization
  module Policies
    class ApplicationPolicy
      attr_reader :user, :record
      def initialize(context, record)
        raise Pundit::NotAuthorizedError, "Usuario no autenticado" unless context
        if context.is_a?(Authorization::UserContext)
          @user = context.user
          @permissions = context.permissions
        else
          @user = context
          @permissions = nil
        end
        @record = record
      end
      def index? = false
      def show? = false
      def create? = false
      def update? = false
      def destroy? = false
      private
      def super_admin? = user.super_admin?
      def has_permission?(slug)
        return true if super_admin?
        if @permissions
          @permissions.include?(slug)
        else
          Authorization::Interactors::FetchUserPermissions.new.call(user_id: user.id).include?(slug)
        end
      end
    end
  end
end
