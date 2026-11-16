module Api
  module V1
    # ASC-4 fase 6: modo demo.
    #   POST /api/v1/demo/session  pública, con rate limit (rack-attack): sesión de solo lectura en la cuenta demo.
    #   POST /api/v1/demo/switch   solo superadministrador: la misma sesión demo, emitida por la API.
    # Responde la misma forma que el login, con user.demo = true, refresh_token nil y meta.expires_in.
    class DemoController < Api::V1::BaseController
      skip_before_action :authenticate_request!, only: [ :create_session ]
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def create_session
        render_session(Demo::Interactors::IssueDemoSession.new.call)
      rescue Demo::Errors::NotSeeded
        render_not_available
      end

      def switch
        render_session(Demo::Interactors::SwitchToDemo.new.call(user: current_user))
      rescue Demo::Errors::Forbidden
        render_forbidden("Solo el superadministrador puede usar el modo demo")
      rescue Demo::Errors::NotSeeded
        render_not_available
      end

      private

      def render_session(result)
        body = Auth::Presenters::AuthPresenter.user_with_tokens(
          user: result[:user], access_token: result[:access_token], refresh_token: result[:refresh_token]
        )
        body[:meta][:expires_in] = result[:expires_in]
        body[:meta][:demo] = true
        render json: body, status: :ok
      end

      def render_not_available
        render json: { errors: [ { status: "404", code: "demo_not_available", detail: "La demo no está disponible" } ] },
               status: :not_found
      end
    end
  end
end
