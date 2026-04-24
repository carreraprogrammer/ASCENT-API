class AgentInsight < ApplicationRecord
  belongs_to :account

  TRIGGER_REASONS = %w[initial month_change balance_drift track_change deploy_drift manual].freeze

  validates :period_month, :period_year, :generated_at, presence: true
  validates :trigger_reason, inclusion: { in: TRIGGER_REASONS }, allow_nil: true

  scope :for_period, ->(month, year) { where(period_month: month, period_year: year) }

  def self.current_for(account_id:, month:, year:)
    where(account_id: account_id)
      .for_period(month, year)
      .order(generated_at: :desc)
      .first
  end

  def stale?
    generated_at < 7.days.ago
  end
end
