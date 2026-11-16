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
      # ASC-4 fase 2: a dónde vuelve el callback. "native" (iOS/Android) usa el deep link como siempre;
      # "web" termina con un 302 a FRONTEND_URL + /auth/gmail/callback.
      PLATFORMS        = %w[web native].freeze
      NATIVE_ORIGINS   = %w[capacitor://localhost ionic://localhost https://localhost http://localhost].freeze

      class << self
        # Genera la URL de autorización de Google.
        # Codifica el account_id en el state (firmado con la clave de la app).
        # platform: "web" agrega el destino al state firmado; "native" (o nil) deja el state igual que antes.
        def authorization_url(account_id:, platform: nil)
          payload = platform.to_s == "web" ? "#{account_id}:web" : account_id.to_s
          state = Rails.application.message_verifier(:gmail_oauth).generate(payload, expires_in: 10.minutes)
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
          account_id = decode_state(state)[:account_id]

          account = Account.find(account_id)
          # ASC-4: la cuenta demo nunca conecta Gmail.
          raise ArgumentError, "la cuenta demo no conecta Gmail" if account.owner_user&.demo

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

        # Plataforma que inició la conexión. Un parámetro explícito (web/ios/android) manda; si no, el Origin
        # del navegador: la app de Capacitor llama desde capacitor://localhost (iOS) o https://localhost
        # (Android); la web, desde su dominio. Sin Origin se asume la app, como hasta ahora.
        def platform_for(param: nil, origin: nil)
          case param.to_s.downcase
          when "web" then return "web"
          when "ios", "android", "native" then return "native"
          end
          return "native" if origin.blank? || NATIVE_ORIGINS.include?(origin.to_s.downcase.chomp("/"))

          "web"
        end

        # Lee el state firmado: { account_id:, platform: }. Lanza ArgumentError si es inválido o expiró.
        def decode_state(state)
          payload = Rails.application.message_verifier(:gmail_oauth).verify(state).to_s
          account_id, platform = payload.split(":", 2)
          { account_id: account_id, platform: platform == "web" ? "web" : "native" }
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          raise ArgumentError, "state inválido o expirado"
        end

        # A dónde volver aunque el state no sirva (error de Google, state vencido): sin state legible, la app.
        def return_platform(state)
          return "native" if state.blank?

          decode_state(state)[:platform]
        rescue ArgumentError
          "native"
        end

        # Devuelve la conexión con access_token fresco.
        # Si el token expiró lo renueva antes de devolver.
        # Lanza ActiveRecord::RecordNotFound si la cuenta no tiene email conectado.
        def fresh_connection(account_id:)
          conn = EmailConnection.find_by!(account_id: account_id)

          if conn.expired?
            begin
              tokens = fetch_tokens(
                grant_type:    "refresh_token",
                refresh_token: conn.refresh_token
              )
            rescue => e
              # Refresh token muerto/revocado: el push y el nocturno seguirán fallando
              # en silencio hasta que el usuario reconecte. Lo marcamos y avisamos.
              flag_reconnect_required(conn, reason: e.message)
              raise
            end
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
          conn.reconnect_required_at = nil # reconexión exitosa: limpia el aviso
          # refresh_token solo viene en el primer exchange (access_type: offline + prompt: consent)
          conn.refresh_token = tokens["refresh_token"] if tokens["refresh_token"].present?
          conn.save!
        end

        # Marca la conexión como rota y emite un aviso de "reconectá Gmail" para la
        # app. El flag es persistente (lo lee el endpoint de estado); el agent_event
        # es el nudge inmediato si el usuario está activo. Solo avisa una vez por
        # caída para no spamear en cada reintento diario.
        def flag_reconnect_required(conn, reason: nil)
          already_flagged = conn.reconnect_required_at.present?
          unless already_flagged
            conn.update_column(:reconnect_required_at, Time.current)
            Rails.logger.warn("[GmailOauth] account=#{conn.account_id} requiere reconexión: #{reason}")
          end

          # Aviso resiliente: el refresh falla en cada intento de lectura (cada push /
          # nocturno) mientras el token esté revocado. En vez de avisar una sola vez
          # (y que el usuario se lo pierda), garantizamos que SIEMPRE haya una tarjeta
          # de reconexión pendiente: si la anterior ya fue consumida, emitimos otra.
          pending = AgentUiEvent
            .where(account_id: conn.account_id, event_type: "show_card", consumed_at: nil)
            .where("payload ->> 'action' = ?", "reconnect_gmail")
            .exists?
          return if pending

          AgentUiEvent.create!(
            account_id: conn.account_id,
            event_type: "show_card",
            payload: {
              "title"  => "Reconectá tu Gmail",
              "body"   => "Perdí el acceso a tu correo y dejé de registrar tus movimientos automáticamente. Reconectá Gmail desde Ajustes para retomar.",
              "tone"   => "warning",
              "action" => "reconnect_gmail"
            }
          )
        rescue => e
          Rails.logger.error("[GmailOauth] no se pudo emitir aviso de reconexión account=#{conn.account_id}: #{e.message}")
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
