module Api
  module V1
    class AgentInsightsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/agent_insights/latest
      # El insight visible más reciente — para la card del dashboard.
      def latest
        return unless require_scope!("summary:read")

        insight = agent_insight_repo.latest_for(account_id: current_account.id)

        render json: { data: insight }
      end

      # PATCH /api/v1/agent_insights/:id
      # Actualiza el status: seen | actioned | dismissed.
      def update_status
        return unless require_scope!("summary:read")

        status = params[:status].to_s

        unless AgentInsight::STATUSES.include?(status)
          return render_unprocessable("status inválido — usar: #{AgentInsight::STATUSES.join(', ')}")
        end

        insight = agent_insight_repo.update_status(
          id:         params[:id].to_i,
          account_id: current_account.id,
          status:     status
        )

        render json: { data: insight }

      rescue Finanzas::Errors::InvalidTransaction => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      private

      def agent_insight_repo
        @agent_insight_repo ||= Finanzas::Repositories::AgentInsightRepository.new
      end
    end
  end
end
