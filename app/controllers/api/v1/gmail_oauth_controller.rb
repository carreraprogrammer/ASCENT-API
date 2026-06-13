module Api
  module V1
    # Maneja el flujo OAuth de Gmail para conectar el email del usuario.
    #
    # Endpoints autenticados (JWT de usuario):
    #   GET    /api/v1/me/email_connection        → estado de la conexión
    #   POST   /api/v1/auth/gmail                 → inicia OAuth, devuelve URL
    #   DELETE /api/v1/me/email_connection        → desconecta
    #
    # Endpoint interno (service token + X-Account-Id):
    #   GET    /api/v1/me/email_connection/token  → access_token fresco para el agente
    #
    # Callback público (Google redirige aquí, sin JWT):
    #   GET    /api/v1/auth/gmail/callback
    class GmailOauthController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # El callback viene de Google sin JWT — solo este action lo salta
      skip_before_action :authenticate_request!, only: [:callback]

      # GET /api/v1/me/email_connection
      def status
        conn = EmailConnection.find_by(account_id: current_account.id)
        if conn
          render json: {
            data: {
              connected:   true,
              provider:    "gmail",
              bank_senders: conn.bank_senders_list
            }
          }
        else
          render json: {
            data: {
              connected:   false,
              provider:    nil,
              bank_senders: []
            }
          }
        end
      end

      # POST /api/v1/auth/gmail
      # La app llama esto, recibe la URL y abre el browser OAuth.
      def start
        url = Auth::Interactors::GmailOauth.authorization_url(account_id: current_account.id)
        render json: { data: { authorization_url: url } }
      end

      # GET /api/v1/auth/gmail/callback
      # Google redirige aquí tras la aprobación del usuario.
      # Seguridad: el account_id viene en el `state` firmado por la app (10 min TTL).
      def callback
        error = params[:error]
        code  = params[:code]
        state = params[:state]

        if error.present?
          return redirect_to_app(status: "error", reason: error)
        end

        if code.blank? || state.blank?
          return redirect_to_app(status: "error", reason: "missing_params")
        end

        Auth::Interactors::GmailOauth.exchange_code(code: code, state: state)
        redirect_to_app(status: "connected")

      rescue ArgumentError => e
        Rails.logger.warn("[GmailOauth] callback state inválido: #{e.message}")
        redirect_to_app(status: "error", reason: "invalid_state")
      rescue => e
        Rails.logger.error("[GmailOauth] callback error: #{e.message}")
        redirect_to_app(status: "error", reason: "exchange_failed")
      end

      # DELETE /api/v1/me/email_connection
      def disconnect
        Auth::Interactors::GmailOauth.disconnect(account_id: current_account.id)
        render json: { data: { connected: false } }
      end

      # GET /api/v1/me/email_connection/token
      # Usado por el agente nocturno (service token + X-Account-Id).
      # Devuelve access_token fresco + bank_senders configurados.
      def token
        return unless require_scope!("agent:write")

        conn = Auth::Interactors::GmailOauth.fresh_connection(account_id: current_account.id)
        render json: {
          data: {
            access_token: conn.access_token,
            provider:     "gmail",
            bank_senders: conn.bank_senders_list
          }
        }

      rescue ActiveRecord::RecordNotFound
        render json: { data: { connected: false } }, status: :not_found
      rescue => e
        Rails.logger.error("[GmailOauth] token refresh error: #{e.message}")
        render_unprocessable("No se pudo renovar el token de Gmail")
      end

      # PATCH /api/v1/me/email_connection/senders
      # Actualiza la lista de remitentes bancarios del usuario.
      # Llamado por el agente cuando descubre nuevos remitentes, o por la app.
      def update_senders
        senders = params[:bank_senders]
        unless senders.is_a?(Array)
          return render_unprocessable("bank_senders debe ser un array de strings")
        end

        conn = Auth::Interactors::GmailOauth.update_senders(
          account_id: current_account.id,
          senders:    senders
        )
        render json: { data: { bank_senders: conn.bank_senders_list } }

      rescue ActiveRecord::RecordNotFound
        render json: { errors: [{ status: "404", detail: "Gmail no conectado" }] }, status: :not_found
      rescue => e
        Rails.logger.error("[GmailOauth] update_senders error: #{e.message}")
        render_unprocessable("No se pudo actualizar los remitentes")
      end

      private

      # No usamos `redirect_to` a un esquema custom (daniel15k://): los navegadores
      # externos / Custom Tabs no siguen un 302 hacia un esquema custom sin un gesto
      # del usuario, así que el wizard quedaba "estancado" tras finalizar aunque la
      # conexión ya estuviera hecha. En su lugar servimos una página HTML que dispara
      # el deep link por JS al cargar y deja un botón de respaldo para volver a la app.
      def redirect_to_app(status:, reason: nil)
        deep_link = ENV.fetch("APP_DEEP_LINK_BASE", "daniel15k://auth/gmail")
        query     = { status: status }
        query[:reason] = reason if reason.present?
        target = "#{deep_link}?#{query.to_query}"

        render html: deep_link_page(target, status: status).html_safe, content_type: "text/html"
      end

      def deep_link_page(target, status:)
        ok       = status == "connected"
        title    = ok ? "Gmail conectado" : "No se pudo conectar Gmail"
        message  = ok ? "Listo. Volviendo a la app…" : "Hubo un problema. Volvé a la app e intentá de nuevo."
        href     = CGI.escapeHTML(target)
        js_url   = target.to_json

        <<~HTML
          <!DOCTYPE html>
          <html lang="es">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{CGI.escapeHTML(title)}</title>
            <style>
              body { font-family: -apple-system, system-ui, sans-serif; background: #0f172a; color: #f8fafc;
                     display: flex; min-height: 100vh; margin: 0; align-items: center; justify-content: center; text-align: center; }
              .card { padding: 2rem; max-width: 22rem; }
              h1 { font-size: 1.25rem; margin: 0 0 .5rem; }
              p { color: #cbd5e1; margin: 0 0 1.5rem; }
              a.btn { display: inline-block; background: #22c55e; color: #052e16; text-decoration: none;
                      font-weight: 600; padding: .75rem 1.5rem; border-radius: .75rem; }
            </style>
          </head>
          <body>
            <div class="card">
              <h1>#{CGI.escapeHTML(title)}</h1>
              <p>#{CGI.escapeHTML(message)}</p>
              <a class="btn" href="#{href}">Volver a la aplicación</a>
            </div>
            <script>
              // Intenta abrir el deep link inmediatamente; el botón es el respaldo.
              window.location.replace(#{js_url});
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end
