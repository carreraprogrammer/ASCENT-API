module Finanzas
  module Repositories
    class AgentInsightRepository
      # El insight visible más reciente para el dashboard.
      # @return [Hash, nil]
      def latest_for(account_id:)
        record = ::AgentInsight
          .for_account(account_id)
          .visible
          .latest
          .first
        map_to_entity(record) if record
      end

      # Actualiza el status (seen / actioned / dismissed).
      # @return [Hash]
      def update_status(id:, account_id:, status:)
        record = ::AgentInsight.find_by!(id: id, account_id: account_id)
        record.update!(status: status)
        map_to_entity(record)
      rescue ActiveRecord::RecordNotFound
        raise Finanzas::Errors::InvalidTransaction, "AgentInsight #{id} not found"
      end

      private

      def map_to_entity(record)
        {
          id:              record.id,
          account_id:      record.account_id,
          insightable_type: record.insightable_type,
          insightable_id:  record.insightable_id,
          insight_kind:    record.insight_kind,
          title:           record.title,
          body:            record.body,
          status:          record.status,
          agent_reasoning: record.agent_reasoning,
          generated_at:    record.generated_at,
          created_at:      record.created_at,
          analysis_date:   record.insightable.try(:analysis_date)&.iso8601
        }
      end
    end
  end
end
