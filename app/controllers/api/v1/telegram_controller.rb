module Api
  module V1
    class TelegramController < ActionController::API
      # Telegram llama este endpoint sin JWT.
      # Protegido por CHAT_ID: solo procesa updates del chat autorizado.

      AUTHORIZED_CHAT_ID = ENV["TELEGRAM_CHAT_ID"].to_i

      # POST /api/v1/telegram/webhook
      # Recibe updates de Telegram. Procesa callbacks en tiempo real, almacena el resto.
      def webhook
        update = JSON.parse(request.body.read) rescue {}
        update_id = update["update_id"]

        if (cq = update["callback_query"])
          return head :ok unless authorized?(cq.dig("from", "id"))
          TelegramUpdate.store!(update_id: update_id, update_type: "callback_query", payload: cq)
          handle_callback_query(cq)

        elsif (msg = update["message"])
          return head :ok unless authorized?(msg.dig("chat", "id"))
          TelegramUpdate.store!(update_id: update_id, update_type: "message", payload: msg)
        end

        head :ok
      end

      # GET /api/v1/telegram/updates
      # El agente nocturno llama esto en lugar de getUpdates directamente.
      # Devuelve updates no consumidos y los marca como consumidos.
      def updates
        rows = TelegramUpdate.unconsumed.limit(100)
        result = rows.map { |r| { id: r.id, update_type: r.update_type, payload: r.payload } }
        rows.update_all(consumed: true)
        render json: { ok: true, updates: result, total: result.size }
      end

      private

      def authorized?(chat_id)
        chat_id.to_i == AUTHORIZED_CHAT_ID
      end

      def handle_callback_query(cq)
        cq_id = cq["id"]
        data  = cq["data"].to_s
        parts = data.split(":")

        case parts.first
        when "cat"
          txn_id, subcat_code = parts[1], parts[2]
          result = update_transaction(txn_id, subcategory_code: subcat_code, status: "confirmed")
          if result
            answer_callback_query(cq_id, "✅ #{subcat_code}")
            send_message("✅ <b>#{result[:concept]}</b> → <i>#{subcat_code}</i>")
          else
            answer_callback_query(cq_id, "❌ Error al actualizar")
          end

        when "confirm"
          txn_id = parts[1]
          result = update_transaction(txn_id, status: "confirmed")
          if result
            answer_callback_query(cq_id, "✅ Confirmado")
            send_message("✅ <b>#{result[:concept]}</b> confirmado")
          else
            answer_callback_query(cq_id, "❌ Error al actualizar")
          end

        when "skip"
          txn_id = parts[1]
          update_transaction(txn_id, clarification_resolved_at: Time.current.iso8601)
          answer_callback_query(cq_id, "⏭ Pospuesto")

        else
          answer_callback_query(cq_id, "✅ Ok")
        end
      rescue StandardError => e
        Rails.logger.error("[TelegramController] handle_callback_query failed: #{e.message}")
        answer_callback_query(cq["id"], "❌ Error interno") rescue nil
      end

      def update_transaction(id, attrs)
        email = ENV["DANIEL15K_EMAIL"].presence || ENV["API_EMAIL"].presence
        user  = email ? ::User.find_by(email: email) : ::User.order(:id).first
        return nil unless user
        transaction = Finanzas::Interactors::UpdateTransaction.new.call(
          id: id, account_id: user.default_account.id, **attrs
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
        http.use_ssl = true
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
