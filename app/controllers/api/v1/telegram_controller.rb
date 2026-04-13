module Api
  module V1
    class TelegramController < ActionController::API
      # Telegram llama este endpoint sin JWT — no hereda de BaseController.
      # Protegido únicamente por CHAT_ID: solo procesa callbacks del chat autorizado.

      AUTHORIZED_CHAT_ID = ENV["TELEGRAM_CHAT_ID"].to_i

      def webhook
        update = JSON.parse(request.body.read) rescue {}

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
        parts = data.split(":")

        case parts.first
        when "cat"
          txn_id, subcat_code = parts[1], parts[2]
          result = update_transaction(txn_id, subcategory_code: subcat_code, status: "confirmed")
          if result
            answer_callback_query(cq_id, "✅ #{subcat_code}")
            send_message("✅ <b>#{result[:concept]}</b> → <i>#{subcat_code}</i> confirmado")
          else
            answer_callback_query(cq_id, "❌ Error al actualizar")
          end

        when "confirm"
          txn_id = parts[1]
          result = update_transaction(txn_id, status: "confirmed")
          if result
            answer_callback_query(cq_id, "✅ Confirmado")
            send_message("✅ <b>#{result[:concept]}</b> confirmado ($#{result[:amount].to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1.'). reverse})")
          else
            answer_callback_query(cq_id, "❌ Error al actualizar")
          end

        when "skip"
          txn_id = parts[1]
          result = update_transaction(txn_id, clarification_resolved_at: Time.current.iso8601)
          if result
            answer_callback_query(cq_id, "⏭ Pospuesto")
          else
            answer_callback_query(cq_id, "❌ Error al actualizar")
          end

        else
          answer_callback_query(cq_id, "✅ Ok")
        end
      rescue StandardError => e
        Rails.logger.error("[TelegramController] handle_callback_query failed: #{e.message}")
        answer_callback_query(cq["id"], "❌ Error interno") rescue nil
      end

      def update_transaction(id, attrs)
        user = ::User.first
        return nil unless user

        transaction = Finanzas::Interactors::UpdateTransaction.new.call(
          id: id, user_id: user.id, **attrs
        )
        { concept: transaction.concept, amount: transaction.amount }
      rescue StandardError => e
        Rails.logger.error("[TelegramController] update_transaction #{id} failed: #{e.message}")
        nil
      end

      def answer_callback_query(cq_id, text)
        tg_post("answerCallbackQuery", callback_query_id: cq_id, text: text, show_alert: false)
      end

      def send_message(text)
        tg_post("sendMessage", chat_id: AUTHORIZED_CHAT_ID, text: text, parse_mode: "HTML")
      end

      def tg_post(method, **payload)
        token = ENV["TELEGRAM_BOT_TOKEN"]
        return unless token.present?

        uri  = URI("https://api.telegram.org/bot#{token}/#{method}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl    = true
        http.open_timeout = 5
        http.read_timeout = 5

        req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        req.body = payload.to_json
        http.request(req)
      rescue StandardError => e
        Rails.logger.error("[TelegramController] #{method} failed: #{e.message}")
      end
    end
  end
end
