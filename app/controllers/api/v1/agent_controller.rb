module Api
  module V1
    # Endpoints internos para el Brain agent — autenticados solo con service token.
    # No requieren X-Account-Id porque operan sobre todas las cuentas.
    class AgentController < ActionController::API
      before_action :authenticate_service_token!

      # GET /api/v1/agent/accounts/active
      # Devuelve todas las accounts activas con los datos que el scheduler necesita
      # para iterar la revisión nocturna: id, telegram_chat_id.
      def active_accounts
        accounts = Account.active.includes(:owner_user).order(:id)
        render json: {
          data: accounts.map { |a|
            {
              id:               a.id,
              name:             a.name,
              telegram_chat_id: a.telegram_chat_id
            }
          }
        }
      end

      private

      def authenticate_service_token!
        token = request.headers["Authorization"]&.split(" ")&.last
        @current_service_account = token.present? && ServiceAccount.authenticate(token)

        return if @current_service_account

        render json: {
          errors: [ { status: "401", code: "unauthorized", detail: "Service token inválido" } ]
        }, status: :unauthorized
      end
    end
  end
end
