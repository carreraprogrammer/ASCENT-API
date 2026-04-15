module Api
  module V1
    class ApplicationController < ::ApplicationController
      include Authorizable

      class AuthenticationError < StandardError; end

      before_action :authenticate_request!

      private

      def authenticate_request!
        token = request.headers["Authorization"]&.split(" ")&.last
        raise JwtService::InvalidToken if token.blank?

        authenticate_user_request!(token)
      rescue JwtService::ExpiredToken
        render json: {
          errors: [ { status: "401", code: "unauthorized", detail: "Token inválido o expirado" } ]
        }, status: :unauthorized and return
      rescue JwtService::InvalidToken, Auth::Errors::InvalidToken
        authenticate_service_account_request!(token)
      rescue ActiveRecord::RecordNotFound
        render json: {
          errors: [ { status: "404", code: "account_not_found", detail: "Cuenta no encontrada" } ]
        }, status: :not_found and return
      rescue AuthenticationError
        render json: {
          errors: [ { status: "401", code: "unauthorized", detail: "Token inválido o expirado" } ]
        }, status: :unauthorized and return
      end

      def authenticate_user_request!(token)
        @jwt_payload = JwtService.decode(token)
        @current_user = Auth::Interactors::FetchUser.new.call(id: @jwt_payload[:user_id])
        @current_account = resolve_user_account(@current_user)
      end

      def authenticate_service_account_request!(token)
        @current_service_account = ServiceAccount.authenticate(token)
        raise AuthenticationError if @current_service_account.blank?

        @current_agent_type = AgentType.active.find_by!(slug: requested_agent_type_slug)
        @current_account = Account.active.find(requested_account_id)
        @current_delegation = Delegation.active.find_by!(
          service_account: @current_service_account,
          account: @current_account,
          agent_type: @current_agent_type,
          user_id: @current_account.owner_user_id
        )
        @current_user = nil
        @jwt_payload = {
          service_account_id: @current_service_account.id,
          account_id: @current_account.id,
          agent_type: @current_agent_type.slug,
          type: "service_access"
        }
      end

      def resolve_user_account(user)
        scope = Account.active.where(owner_user_id: user.id)

        if requested_account_id.present?
          scope.find(requested_account_id)
        else
          scope.order(:id).first || raise(ActiveRecord::RecordNotFound)
        end
      end

      def requested_account_id
        request.headers["X-Account-Id"].presence || params[:account_id].presence
      end

      def requested_agent_type_slug
        request.headers["X-Agent-Type"].presence || "finance_coach"
      end

      def current_user
        @current_user
      end

      def current_account
        @current_account
      end

      def current_service_account
        @current_service_account
      end

      def current_agent_type
        @current_agent_type
      end

      def current_delegation
        @current_delegation
      end

      def current_actor
        current_service_account || current_user
      end

      def current_actor_type
        current_service_account.present? ? "service_account" : "user"
      end

      def service_account_request?
        current_service_account.present?
      end

      def current_owner_user_id
        current_account&.owner_user_id || current_user&.id
      end

      def require_scope!(scope)
        return true unless service_account_request?
        return true if current_delegation&.allows_scope?(scope)

        render json: {
          errors: [ { status: "403", code: "forbidden", detail: "Scope '#{scope}' no permitido" } ]
        }, status: :forbidden and return false
      end

      def pundit_user
        Authorization::UserContext.new(
          user: current_user,
          permissions: Array(@jwt_payload&.dig(:permissions))
        )
      end

      def normalized_sort_dir(value, default: "asc")
        value.to_s.downcase == "desc" ? "desc" : default
      end

      def normalized_presence(value)
        value.respond_to?(:strip) ? value.strip.presence : value.presence
      end

      def normalized_boolean_filter(value)
        return nil if value.nil?

        normalized = value.to_s.strip.downcase
        return nil if normalized.blank? || normalized == "all"

        ActiveModel::Type::Boolean.new.cast(normalized)
      end
    end
  end
end
