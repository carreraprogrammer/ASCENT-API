module Auth
  module Interactors
    # Registra o renueva el gmail.watch() para un account.
    #
    # Uso:
    #   GmailWatchRegistrar.call(account_id: 42)
    #
    # Efectos:
    #   - Persiste gmail_address, gmail_history_id, gmail_watch_expires_at en EmailConnection.
    #   - El watch expira en ~7 días. GmailWatchRenewalJob lo renueva antes de que expire.
    class GmailWatchRegistrar
      GMAIL_PROFILE_URL = "https://gmail.googleapis.com/gmail/v1/users/me/profile"
      GMAIL_WATCH_URL   = "https://gmail.googleapis.com/gmail/v1/users/me/watch"

      def self.call(account_id:)
        new.call(account_id: account_id)
      end

      def call(account_id:)
        conn  = GmailOauth.fresh_connection(account_id: account_id)
        token = conn.access_token

        profile     = gmail_get(GMAIL_PROFILE_URL, token)
        gmail_address = profile["emailAddress"]

        watch_response = gmail_post(GMAIL_WATCH_URL, token, {
          topicName: ENV.fetch("GOOGLE_PUBSUB_TOPIC"),
          labelIds:  [ "INBOX" ]
        })

        history_id  = watch_response["historyId"]
        # expiration viene en milisegundos desde epoch
        expires_at  = Time.at(watch_response["expiration"].to_i / 1000)

        conn.update!(
          gmail_address:          gmail_address,
          gmail_history_id:       history_id,
          gmail_watch_expires_at: expires_at
        )

        Rails.logger.info("[GmailWatchRegistrar] account=#{account_id} gmail=#{gmail_address} expires=#{expires_at}")
        conn
      rescue KeyError => e
        raise "GOOGLE_PUBSUB_TOPIC no configurado: #{e.message}"
      rescue => e
        Rails.logger.error("[GmailWatchRegistrar] account=#{account_id} error: #{e.message}")
        raise
      end

      private

      def gmail_get(url, token)
        uri  = URI(url)
        req  = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{token}"
        response = http_client(uri).request(req)
        data = JSON.parse(response.body)
        raise "Gmail API error: #{data['error']}" if data["error"]
        data
      end

      def gmail_post(url, token, body)
        uri  = URI(url)
        req  = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Content-Type"]  = "application/json"
        req.body = body.to_json
        response = http_client(uri).request(req)
        data = JSON.parse(response.body)
        raise "Gmail API error: #{data['error']}" if data["error"]
        data
      end

      def http_client(uri)
        http          = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl  = true
        http.open_timeout = 10
        http.read_timeout = 15
        http
      end
    end
  end
end
