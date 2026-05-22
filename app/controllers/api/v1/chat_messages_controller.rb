module Api
  module V1
    class ChatMessagesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/chat_messages?channel=app&limit=20
      def index
        return unless require_scope!("summary:read")

        channel = params[:channel].presence || "app"
        limit   = [[params[:limit].to_i, 1].max, 50].min
        limit   = 20 if limit.zero?

        messages = ChatMessage
          .where(account_id: current_account.id, channel: channel)
          .order(created_at: :asc)
          .last(limit)

        render json: {
          data: messages.map { |m| { role: m.role, content: m.content, created_at: m.created_at } }
        }
      end

      # POST /api/v1/chat_messages
      # Llamado por el agente Python para persistir respuestas del asistente.
      def create
        return unless require_scope!("agent:write")

        msg = ChatMessage.create!(
          account_id: current_account.id,
          channel:    params[:channel].presence || "app",
          role:       params[:role].to_s,
          content:    params[:content].to_s
        )

        render json: { data: { id: msg.id } }, status: :created

      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.message)
      end
    end
  end
end
