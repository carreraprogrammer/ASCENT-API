module Api
  module V1
    class ApplicationController < ::ApplicationController
      include Authorizable

      before_action :authenticate_request!

      private

      def authenticate_request!
        token = request.headers["Authorization"]&.split(" ")&.last
        @jwt_payload = JwtService.decode(token)
        @current_user = ::User.find(@jwt_payload[:user_id])
      rescue JwtService::ExpiredToken, JwtService::InvalidToken, ActiveRecord::RecordNotFound
        render json: {
          errors: [ { status: "401", code: "unauthorized", detail: "Token inválido o expirado" } ]
        }, status: :unauthorized and return
      end

      def current_user
        @current_user
      end

      def pundit_user
        Authorization::UserContext.new(
          user: current_user,
          permissions: Array(@jwt_payload&.dig(:permissions))
        )
      end
    end
  end
end
