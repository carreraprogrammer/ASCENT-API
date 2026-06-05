module Auth
  module Interactors
    # Maneja el flujo completo de Gmail OAuth para una cuenta.
    #
    # Uso:
    #   GmailOauth.authorization_url(account_id:)   → URL para redirigir al usuario
    #   GmailOauth.exchange_code(code:, state:)     → guarda tokens, devuelve account
    #   GmailOauth.fresh_token(account_id:)         → access_token fresco (renueva si expiró)
    #   GmailOauth.disconnect(account_id:)          → borra EmailConnection
    class GmailOauth
      GOOGLE_AUTH_URL  = "https://accounts.google.com/o/oauth2/v2/auth"
      GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
      SCOPE            = "https://www.googleapis.com/auth/gmail.readonly"

      class << self
        # Genera la URL de autorización de Google.
        # Codifica el account_id en el state (firmado con la clave de la app).
        def authorization_url(account_id:)
          state = Rails.application.message_verifier(:gmail_oauth).generate(account_id.to_s, expires_in: 10.minutes)
          uri = URI(GOOGLE_AUTH_URL)
          uri.query = URI.encode_www_form(
            client_id:     client_id,
            redirect_uri:  redirect_uri,
            response_type: "code",
            scope:         SCOPE,
            access_type:   "offline",
            prompt:        "consent",      # fuerza refresh_token en cada auth
            state:         state
          )
          uri.to_s
        end

        # Recibe el código de Google, lo intercambia por tokens y los guarda.
        # Devuelve el Account para poder construir el redirect de vuelta a la app.
        def exchange_code(code:, state:)
          account_id = Rails.application.message_verifier(:gmail_oauth).verify(state)

          account = Account.find(account_id)

          tokens = fetch_tokens(grant_type: "authorization_code", code: code)

          upsert_connection(account, tokens)

          # Registrar watch de Pub/Sub en background para no bloquear el redirect
          Thread.new do
            GmailWatchRegistrar.call(account_id: account.id)
          rescue => e
            Rails.logger.error("[GmailOauth] watch registration failed account=#{account.id}: #{e.message}")
          end

          account
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          raise ArgumentError, "state inválido o expirado"
        end

        # Devuelve la conexión con access_token fresco.
        # Si el token expiró lo renueva antes de devolver.
        # Lanza ActiveRecord::RecordNotFound si la cuenta no tiene email conectado.
        def fresh_connection(account_id:)
          conn = EmailConnection.find_by!(account_id: account_id)

          if conn.expired?
            tokens = fetch_tokens(
              grant_type:    "refresh_token",
              refresh_token: conn.refresh_token
            )
            conn.update!(
              access_token: tokens["access_token"],
              expires_at:   Time.current + tokens.fetch("expires_in", 3600).to_i.seconds
            )
          end

          conn
        end

        # Compat alias — devuelve solo el access_token.
        def fresh_token(account_id:)
          fresh_connection(account_id: account_id).access_token
        end

        # Actualiza la lista de remitentes bancarios configurados por el usuario.
        # senders: Array de strings (emails). Vacío = modo keyword automático.
        def update_senders(account_id:, senders:)
          conn = EmailConnection.find_by!(account_id: account_id)
          clean = Array(senders).map(&:strip).select(&:present?).first(30).uniq
          conn.update!(bank_senders: clean.to_json)
          conn
        end

        def disconnect(account_id:)
          EmailConnection.find_by(account_id: account_id)&.destroy!
        end

        def connected?(account_id:)
          EmailConnection.exists?(account_id: account_id)
        end

        private

        def fetch_tokens(grant_type:, **extra_params)
          body = {
            client_id:     client_id,
            client_secret: client_secret,
            redirect_uri:  redirect_uri,
            grant_type:    grant_type,
            **extra_params
          }

          response = Net::HTTP.post(
            URI(GOOGLE_TOKEN_URL),
            URI.encode_www_form(body),
            "Content-Type" => "application/x-www-form-urlencoded"
          )

          data = JSON.parse(response.body)
          raise "Google token error: #{data['error']} — #{data['error_description']}" if data["error"]

          data
        end

        def upsert_connection(account, tokens)
          conn = EmailConnection.find_or_initialize_by(account: account)
          conn.provider      = "gmail"
          conn.access_token  = tokens["access_token"]
          conn.expires_at    = Time.current + tokens.fetch("expires_in", 3600).to_i.seconds
          conn.connected_at  = Time.current
          # refresh_token solo viene en el primer exchange (access_type: offline + prompt: consent)
          conn.refresh_token = tokens["refresh_token"] if tokens["refresh_token"].present?
          conn.save!
        end

        def client_id     = ENV.fetch("GOOGLE_CLIENT_ID")
        def client_secret = ENV.fetch("GOOGLE_CLIENT_SECRET")

        def redirect_uri
          ENV.fetch("GMAIL_OAUTH_REDIRECT_URI",
            "#{ENV.fetch('RAILS_HOST', 'http://localhost:3000')}/api/v1/auth/gmail/callback")
        end
      end
    end
  end
end
