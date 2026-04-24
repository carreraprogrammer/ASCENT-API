module Finanzas
  module Interactors
    # Ruby-pure drift checker — zero LLM cost.
    # Decides whether the existing agent insight is still valid or needs refresh.
    #
    # @param current_state  [Hash]       snapshot of key metrics right now
    # @param last_insight   [AgentInsight, nil]  the most recent persisted insight
    # @param today          [Date, nil]  defaults to Date.today (Colombia time)
    # @return               [Hash]       { should_refresh: bool, reason: String }
    class InsightDriftChecker
      BALANCE_DRIFT_THRESHOLD    = 1_000_000  # COP
      DEPLOY_DRIFT_THRESHOLD     =   500_000  # COP

      def call(current_state:, last_insight:, today: nil)
        today ||= Date.today

        return { should_refresh: true, reason: "initial" } if last_insight.nil?

        snapshot = last_insight.key_metrics_snapshot.symbolize_keys

        return { should_refresh: true, reason: "month_change" }  if month_changed?(snapshot, today)
        return { should_refresh: true, reason: "balance_drift" }  if balance_drifted?(snapshot, current_state)
        return { should_refresh: true, reason: "track_change" }   if track_status_changed?(snapshot, current_state)
        return { should_refresh: true, reason: "deploy_drift" }   if deploy_drifted?(snapshot, current_state)

        { should_refresh: false, reason: "stable" }
      end

      private

      def month_changed?(snapshot, today)
        snapshot[:period_month].to_i != today.month ||
          snapshot[:period_year].to_i  != today.year
      end

      def balance_drifted?(snapshot, current)
        prev_balance = snapshot[:confirmed_balance].to_i
        curr_balance = current[:confirmed_balance].to_i
        (curr_balance - prev_balance).abs > BALANCE_DRIFT_THRESHOLD
      end

      def track_status_changed?(snapshot, current)
        # Fires when any category flipped on_track status
        prev_on_track = Array(snapshot[:categories_on_track]).sort
        curr_on_track = Array(current[:categories_on_track]).sort
        prev_on_track != curr_on_track
      end

      def deploy_drifted?(snapshot, current)
        prev_deploy = snapshot[:safe_to_deploy].to_i
        curr_deploy = current[:safe_to_deploy].to_i
        (curr_deploy - prev_deploy).abs > DEPLOY_DRIFT_THRESHOLD
      end
    end
  end
end
