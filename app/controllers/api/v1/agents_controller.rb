module Api
  module V1
    class AgentsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      COLOMBIA_OFFSET = -5 * 3600
      ALLOWED_INTENTS = %w[budgeting monthly_status overflow general].freeze

      # POST /api/v1/agents/chat
      def chat
        session_id = params[:session_id].presence || SecureRandom.uuid
        WebChatJob.perform_later(
          account_id: current_account.id,
          session_id: session_id,
          message: params[:message].presence,
          event_response: params[:event_response]&.to_unsafe_h
        )
        render json: { data: { session_id: session_id, status: "processing" } }, status: :accepted
      end

      def preflight
        return unless require_scope!("summary:read")

        month, year = requested_period
        intent = normalized_intent
        data = interactor.call(
          account_id: current_account.id,
          month: month,
          year: year,
          intent: intent
        )

        render json: { data: data }
      rescue ArgumentError => e
        render_unprocessable(e.message)
      end

      private

      def requested_period
        now_col = Time.now.utc + COLOMBIA_OFFSET
        [
          (params[:month] || now_col.month).to_i,
          (params[:year] || now_col.year).to_i
        ]
      end

      def normalized_intent
        intent = params[:intent].presence || "general"
        raise ArgumentError, "intent inválido" unless ALLOWED_INTENTS.include?(intent)

        intent
      end

      def interactor
        @interactor ||= Finanzas::Interactors::AgentPreflight.new
      end
    end
  end
end
