module Api
  module V1
    class NightAnalysesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # POST /api/v1/night_analyses
      # Llamado por el agente (service token, scope agent:write).
      # Crea el NightAnalysis + AgentInsight en una sola transacción.
      def create
        return unless require_scope!("agent:write")

        account_id = params[:account_id]&.to_i || current_account.id
        date       = Date.parse(params[:date].to_s)
        metrics    = params.require(:metrics).to_unsafe_h.deep_symbolize_keys
        insight_p  = params.require(:insight).to_unsafe_h.deep_symbolize_keys

        entity = night_analysis_repo.create_with_insight(
          account_id: account_id,
          date:       date,
          metrics:    metrics,
          reasoning:  params[:agent_reasoning].to_s,
          insight:    {
            kind:  insight_p[:kind].to_s,
            title: insight_p[:title].to_s,
            body:  insight_p[:body].to_s
          }
        )

        render json: { data: entity }, status: :created

      rescue Date::Error
        render_unprocessable("date inválida — usar formato YYYY-MM-DD")
      rescue ActionController::ParameterMissing => e
        render_unprocessable(e.message)
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.message)
      end

      # GET /api/v1/night_analyses/metrics?date=YYYY-MM-DD
      # Pre-contextualiza los datos del día para el agente.
      def metrics
        return unless require_scope!("summary:read")

        date = params[:date].present? ? Date.parse(params[:date].to_s) : Date.current

        result = Finanzas::Interactors::BuildNightMetrics.new.call(
          account_id: current_account.id,
          date:       date
        )

        render json: { data: result }

      rescue Date::Error
        render_unprocessable("date inválida — usar formato YYYY-MM-DD")
      end

      # GET /api/v1/night_analyses/:date
      # Devuelve el análisis de una noche específica con su insight.
      # Augmenta needs_review con transacciones pending actuales no resueltas.
      def show
        return unless require_scope!("summary:read")

        date   = Date.parse(params[:date].to_s)
        entity = night_analysis_repo.for_date(account_id: current_account.id, date: date)

        if entity
          render json: { data: augment_pending(entity, current_account.id) }
        else
          render json: { data: nil }, status: :not_found
        end

      rescue Date::Error
        render_unprocessable("date inválida — usar formato YYYY-MM-DD")
      end

      # GET /api/v1/night_analyses
      # Historial reciente de análisis nocturnos.
      def index
        return unless require_scope!("summary:read")

        limit   = [[params[:limit].to_i, 1].max, 90].min
        limit   = 30 if limit.zero?
        entries = night_analysis_repo.recent(account_id: current_account.id, limit: limit)

        render json: { data: entries, meta: { count: entries.size } }
      end

      private

      def augment_pending(entity, account_id)
        stored_ids = ((entity.dig(:transactions_context, :needs_review) || [])
          .map { |r| r[:transaction_id] || r["transaction_id"] }).to_set

        live_pending = ::Transaction
          .where(account_id: account_id, status: "pending")
          .where.not(id: stored_ids)
          .pluck(:id, :concept, :product, :amount, :date)
          .map do |id, concept, product, amount, date|
            {
              transaction_id: id,
              concept:        concept.presence || product,
              amount:         amount.to_i,
              date:           date.to_s,
              reason:         "unconfirmed"
            }
          end

        return entity if live_pending.empty?

        ctx = (entity[:transactions_context] || {}).dup
        ctx[:needs_review] = (ctx[:needs_review] || []) + live_pending
        entity.merge(transactions_context: ctx)
      end

      def night_analysis_repo
        @night_analysis_repo ||= Finanzas::Repositories::NightAnalysisRepository.new
      end
    end
  end
end
