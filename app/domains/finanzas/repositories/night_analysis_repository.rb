module Finanzas
  module Repositories
    class NightAnalysisRepository
      # @param account_id [Integer]
      # @param date       [Date]
      # @return [Hash, nil]
      def for_date(account_id:, date:)
        record = ::NightAnalysis
          .includes(:agent_insight)
          .find_by(account_id: account_id, analysis_date: date)
        map_to_entity(record) if record
      end

      # @return [Array<Hash>]  ordenado desc por fecha
      def recent(account_id:, limit: 30)
        ::NightAnalysis
          .includes(:agent_insight)
          .where(account_id: account_id)
          .order(analysis_date: :desc)
          .limit(limit)
          .map { |r| map_to_entity(r) }
      end

      # Crea el NightAnalysis + AgentInsight de forma atómica.
      # @param account_id [Integer]
      # @param date       [Date]
      # @param metrics    [Hash]   output de BuildNightMetrics
      # @param reasoning  [String] razonamiento del agente
      # @param insight    [Hash]   { kind:, title:, body: }
      # @return [Hash]    entidad del NightAnalysis creado
      def create_with_insight(account_id:, date:, metrics:, reasoning:, insight:)
        ::NightAnalysis.transaction do
          night = ::NightAnalysis.create!(
            account_id:           account_id,
            analysis_date:        date,
            health_status:        metrics[:health_status],
            commitment_gap:       metrics[:commitment_gap],
            daily_burn:           metrics[:daily_burn],
            days_to_next_income:  metrics[:days_to_next_income],
            category_alerts:      metrics[:category_alerts],
            transactions_context: metrics[:transactions_context],
            burn_vs_plan:         metrics[:burn_vs_plan] || [],
            agent_reasoning:      reasoning
          )

          ::AgentInsight.create!(
            account_id:    account_id,
            insightable:   night,
            insight_kind:  insight[:kind],
            title:         insight[:title],
            body:          insight[:body],
            status:        "new",
            generated_at:  Time.current
          )

          map_to_entity(night.reload)
        end
      end

      private

      def map_to_entity(record)
        insight = record.agent_insight

        {
          id:                   record.id,
          account_id:           record.account_id,
          analysis_date:        record.analysis_date,
          health_status:        record.health_status,
          commitment_gap:       record.commitment_gap,
          daily_burn:           record.daily_burn,
          days_to_next_income:  record.days_to_next_income,
          category_alerts:      record.category_alerts,
          transactions_context: record.transactions_context,
          burn_vs_plan:         record.burn_vs_plan,
          agent_reasoning:      record.agent_reasoning,
          created_at:           record.created_at,
          insight: insight ? {
            id:           insight.id,
            insight_kind: insight.insight_kind,
            title:        insight.title,
            body:         insight.body,
            status:       insight.status,
            generated_at: insight.generated_at
          } : nil
        }
      end
    end
  end
end
