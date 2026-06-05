module Api
  module V1
    # Recibe notificaciones push de Gmail via Google Cloud Pub/Sub.
    #
    # Pub/Sub llama POST /api/v1/webhooks/gmail?token=<GMAIL_WEBHOOK_SECRET>
    # sin JWT — la autenticación es el token en query param.
    #
    # El controller siempre responde 200 para que Pub/Sub no reintente.
    # El procesamiento real ocurre en un thread async que llama al Python Brain.
    class GmailWebhookController < ActionController::API
      BRAIN_URL = "#{ENV.fetch('DANIEL15K_BRAIN_URL', 'https://daniel15k-agents-production.up.railway.app')}/agents/gmail-push"

      def create
        unless valid_token?
          head :unauthorized
          return
        end

        data = decode_pubsub_data
        unless data
          head :ok
          return
        end

        gmail_address  = data["emailAddress"]
        new_history_id = data["historyId"].to_s

        conn = EmailConnection.find_by(gmail_address: gmail_address)
        unless conn
          Rails.logger.warn("[GmailWebhook] address desconocido: #{gmail_address}")
          head :ok
          return
        end

        previous_history_id = conn.gmail_history_id.to_s

        # Idempotencia: si ya procesamos este historyId o uno posterior, ignorar.
        if previous_history_id.to_i >= new_history_id.to_i
          head :ok
          return
        end

        account_id = conn.account_id
        connection_id = conn.id
        Thread.new do
          if call_brain(account_id: account_id, history_id: previous_history_id)
            conn = EmailConnection.find(connection_id)
            conn.with_lock do
              if conn.gmail_history_id.to_i < new_history_id.to_i
                conn.update_column(:gmail_history_id, new_history_id)
              end
            end
          end
        end

        head :ok
      end

      private

      def valid_token?
        expected = ENV["GMAIL_WEBHOOK_SECRET"]
        expected.present? && ActiveSupport::SecurityUtils.secure_compare(
          params[:token].to_s, expected
        )
      end

      def decode_pubsub_data
        body = JSON.parse(request.body.read)
        raw  = body.dig("message", "data")
        return nil if raw.blank?
        JSON.parse(Base64.decode64(raw))
      rescue JSON::ParserError, ArgumentError => e
        Rails.logger.warn("[GmailWebhook] payload inválido: #{e.message}")
        nil
      end

      def call_brain(account_id:, history_id:)
        uri  = URI(BRAIN_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10

        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{ENV['DANIEL15K_SERVICE_TOKEN']}"
        req["Content-Type"]  = "application/json"
        req.body = { account_id: account_id, history_id: history_id }.to_json

        response = http.request(req)
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error(
            "[GmailWebhook] brain call failed account=#{account_id}: HTTP #{response.code} #{response.body}"
          )
          return false
        end

        true
      rescue => e
        Rails.logger.error("[GmailWebhook] brain call failed account=#{account_id}: #{e.message}")
        false
      end
    end
  end
end
