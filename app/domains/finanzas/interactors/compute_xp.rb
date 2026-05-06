module Finanzas
  module Interactors
    class ComputeXp
      XP_TABLE = {
        "transaction_confirmed"          => 10,
        "transaction_with_subcategory"   => 5,
        "pending_resolved"               => 15,
        "category_corrected"             => 10,
        "recurring_income_confirmed"     => 20,
        "recurring_obligation_confirmed" => 20,
        "plan_confirmed"                 => 50,
        "month_closed_with_snapshot"     => 75,
        "debt_registered_complete"       => 30,
        "sinking_fund_created"           => 25,
        "streak_7_days"                  => 30,
        "streak_30_days"                 => 100,
        "first_debt_paid_off"            => 200,
        "discretionary_budget_met"       => 40
      }.freeze

      LEVEL_THRESHOLDS = { 0 => 0, 1 => 200, 2 => 600, 3 => 1_500, 4 => 3_500, 5 => 8_000 }.freeze

      def call(account_id:, action_type:, metadata: {})
        xp_amount = XP_TABLE[action_type.to_s]
        return nil if xp_amount.nil?

        ::XpEvent.create!(
          account_id: account_id,
          action_type: action_type,
          xp_amount: xp_amount,
          metadata: metadata
        )

        progress = ::AccountProgress.find_or_initialize_by(account_id: account_id)
        progress.xp ||= 0
        progress.xp += xp_amount
        progress.level = compute_level(progress.xp)
        progress.last_activity_date = Date.current
        progress.avatar_seed = account_id.to_s if progress.avatar_seed.blank?
        progress.save!

        progress
      end

      private

      def compute_level(xp)
        LEVEL_THRESHOLDS.filter_map { |lvl, threshold| lvl if xp >= threshold }.max || 0
      end
    end
  end
end
