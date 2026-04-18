module Api
  module V1
    class AgentUiEventsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/agent_events/pending
      def pending
        events = AgentUiEvent
          .where(account_id: current_account.id)
          .pending
          .for_session(params[:session_id])
          .order(created_at: :asc)

        render json: { data: events.map { |e| serialize(e) } }
      end

      # POST /api/v1/agent_events
      def create
        event = AgentUiEvent.create!(
          account_id: current_account.id,
          session_id: params[:session_id],
          event_type: params[:event_type],
          payload: params[:payload].to_unsafe_h
        )

        render json: { data: serialize(event) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.message)
      end

      # PATCH /api/v1/agent_events/:id/consume
      def consume
        event = AgentUiEvent.find_by!(id: params[:id], account_id: current_account.id)
        event.consume!
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [ { status: "404", detail: "Event not found" } ] }, status: :not_found
      end

      private

      def serialize(event)
        {
          id: event.id,
          event_type: event.event_type,
          payload: event.payload,
          session_id: event.session_id,
          created_at: event.created_at
        }
      end
    end
  end
end
