module Api
  module V1
    class AdminController < ApplicationController
      before_action :require_super_admin!

      def accounts
        accounts = Account.active.includes(:owner_user).order(:id)
        render json: {
          data: accounts.map { |account|
            {
              id: account.id,
              user_id: account.owner_user_id,
              name: account.owner_user.name,
              email: account.owner_user.email
            }
          }
        }
      end

      def impersonate
        target_account = Account.active.includes(:owner_user).find(params[:account_id])
        target_user = target_account.owner_user

        token = JwtService.encode_access_token(
          user_id: target_user.id,
          email: target_user.email,
          super_admin: target_user.super_admin,
          impersonated_by: current_user.id
        )

        render json: {
          data: {
            access_token: token,
            account: {
              id: target_account.id,
              user_id: target_user.id,
              name: target_user.name,
              email: target_user.email
            }
          }
        }
      rescue ActiveRecord::RecordNotFound
        render json: {
          errors: [ { status: "404", code: "not_found", detail: "Cuenta no encontrada" } ]
        }, status: :not_found
      end

      private

      def require_super_admin!
        return if @jwt_payload&.dig(:super_admin)

        render json: {
          errors: [ { status: "403", code: "forbidden", detail: "Acceso restringido" } ]
        }, status: :forbidden
      end
    end
  end
end
