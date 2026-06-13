module Api
  module V1
    # Endpoints internos para el Brain agent — autenticados solo con service token.
    # No requieren X-Account-Id porque operan sobre todas las cuentas.
    class AgentController < ActionController::API
      before_action :authenticate_service_token!

      # GET /api/v1/agent/accounts/active
      # Devuelve todas las accounts activas con los datos que el scheduler necesita
      # para iterar la revisión nocturna.
      # Nota: has_email se determina en el scheduler con DEFAULT_ACCOUNT_ID + GMAIL_ADDRESS
      # hasta que Fase 0.6 (Gmail OAuth por cuenta) esté implementado.
      def active_accounts
        accounts = Account.active.includes(:owner_user).order(:id)
        render json: {
          data: accounts.map { |a|
            {
              id:   a.id,
              name: a.name
            }
          }
        }
      end

      # POST /api/v1/agent/gmail/renew_watches
      # Renueva los gmail.watch() próximos a expirar (< 2 días). El scheduler del
      # Brain lo invoca a diario: sin esto el watch expira cada ~7 días y el push
      # de Gmail muere en silencio hasta que el usuario reconecta a mano.
      def renew_watches
        result = GmailWatchRenewalJob.perform_now
        render json: { data: result }
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
