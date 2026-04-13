module Api
  module V1
    class TelegramController < ActionController::API
      # Telegram llama este endpoint sin JWT — no hereda de BaseController
      # Protegido por TELEGRAM_SECRET_TOKEN en el header X-Telegram-Bot-Api-Secret-Token

      AUTHORIZED_CHAT_ID = ENV["TELEGRAM_CHAT_ID"].to_i

      def webhook
        secret = request.headers["X-Telegram-Bot-Api-Secret-Token"]
        unless secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret, ENV["TELEGRAM_WEBHOOK_SECRET"].to_s)
          head :unauthorized and return
        end

        body = request.body.read
        update = JSON.parse(body) rescue {}

        if (cq = update.dig("callback_query"))
          handle_callback_query(cq)
        end

        head :ok
      end

      private

      def handle_callback_query(cq)
        return unless cq.dig("from", "id").to_i == AUTHORIZED_CHAT_ID

        cq_id = cq["id"]
        data  = cq["data"].to_s

        text = case data.split(":").first
        when "cat"     then "✅ Categoría registrada"
        when "confirm" then "✅ Confirmado"
        when "skip"    then "⏭ Pospuesto"
        else                "✅ Ok"
        end

        answer_callback_query(cq_id, text)
      end

      def answer_callback_query(cq_id, text)
        token = ENV["TELEGRAM_BOT_TOKEN"]
        return unless token.present?

        uri  = URI("https://api.telegram.org/bot#{token}/answerCallbackQuery")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 5

        req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        req.body = { callback_query_id: cq_id, text: text, show_alert: false }.to_json
        http.request(req)
      rescue StandardError => e
        Rails.logger.error("[TelegramController] answerCallbackQuery failed: #{e.message}")
      end
    end
  end
end
