module Api
  module V1
    class AgentInsightsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/agent_insights/current?month=&year=
      def current
        return unless require_scope!("summary:read")

        now_col    = Time.now.utc + (-5 * 3600)
        month      = (params[:month] || now_col.month).to_i
        year       = (params[:year]  || now_col.year).to_i
        account_id = current_account.id

        insight = AgentInsight.current_for(account_id: account_id, month: month, year: year)

        if insight
          render json: { data: serialize(insight) }
        else
          render json: { data: nil }
        end
      end

      # POST /api/v1/agent_insights
      # Called by the agent cron (service token required).
      def create
        return unless require_scope!("agent:write")

        account_id = params[:account_id]&.to_i || current_account.id

        insight = AgentInsight.create!(
          account_id:          account_id,
          period_month:        params[:period_month].to_i,
          period_year:         params[:period_year].to_i,
          generated_at:        params[:generated_at] || Time.current,
          key_metrics_snapshot: (params[:key_metrics_snapshot] || {}).to_unsafe_h,
          recommendations:     (params[:recommendations] || {}).to_unsafe_h,
          reasoning:           params[:reasoning],
          signals:             Array(params[:signals]),
          safe_to_deploy_amount: params[:safe_to_deploy_amount]&.to_i,
          trigger_reason:      params[:trigger_reason]
        )

        render json: { data: serialize(insight) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.message)
      end

      private

      def serialize(insight)
        {
          id:                    insight.id,
          account_id:            insight.account_id,
          period_month:          insight.period_month,
          period_year:           insight.period_year,
          generated_at:          insight.generated_at,
          key_metrics_snapshot:  insight.key_metrics_snapshot,
          recommendations:       insight.recommendations,
          reasoning:             insight.reasoning,
          signals:               insight.signals,
          safe_to_deploy_amount: insight.safe_to_deploy_amount,
          trigger_reason:        insight.trigger_reason,
          stale:                 insight.stale?,
          created_at:            insight.created_at
        }
      end
    end
  end
end
