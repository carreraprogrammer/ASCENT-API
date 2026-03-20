module Authorizable
  extend ActiveSupport::Concern

  included do
    include Pundit::Authorization

    after_action :verify_authorized
    after_action :verify_policy_scoped, only: :index

    rescue_from Pundit::NotAuthorizedError do
      render json: {
        errors: [ { status: "403", code: "forbidden", detail: "No tienes permisos para realizar esta acción" } ]
      }, status: :forbidden
    end
  end

  def current_permissions
    return [] unless current_user
    return Array(@jwt_payload[:permissions]) if defined?(@jwt_payload) && @jwt_payload
    Authorization::Interactors::FetchUserPermissions.new.call(user_id: current_user.id)
  end

  def can?(permission_slug)
    return false unless current_user
    return true if current_user.super_admin?
    current_permissions.include?(permission_slug)
  end
end
