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
        # ASC-4: la cuenta demo no entra (sin agentes programados, nocturnos, consolidados ni avisos).
        accounts = Account.active.not_demo.includes(:owner_user).order(:id)
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

      # GET /api/v1/agent/accounts/demo
      # El id de la cuenta demo, para que el cromo la lea con X-Account-Id cuando el token trae demo: true.
      def demo_account
        render json: { data: { id: Demo::Interactors::DemoAccess.new.demo_account_id, demo: true } }
      rescue Demo::Errors::NotSeeded
        render_demo_not_available
      end

      # POST /api/v1/agent/demo/reset
      # El mismo restablecimiento que bin/rails demo:seed. Lo llama el scheduler del agente cada noche.
      def reset_demo
        result = Demo::Interactors::ResetDemoAccount.new.call
        render json: { data: result.except(:user_id) }
      rescue Demo::Errors::EmailTaken
        render json: { errors: [ { status: "409", code: "demo_email_taken", detail: "DEMO_EMAIL no es un usuario demo" } ] },
               status: :conflict
      end

      private

      def render_demo_not_available
        render json: { errors: [ { status: "404", code: "demo_not_available", detail: "La demo no está sembrada" } ] },
               status: :not_found
      end

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
