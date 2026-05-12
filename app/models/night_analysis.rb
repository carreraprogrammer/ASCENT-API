class NightAnalysis < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :account
  has_one :agent_insight, as: :insightable, dependent: :destroy

  HEALTH_STATUSES = %w[comfortable warning critical].freeze

  validates :analysis_date,  presence: true
  validates :health_status,  inclusion: { in: HEALTH_STATUSES }
  validates :commitment_gap, presence: true
  validates :daily_burn,     presence: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :recent,      -> { order(analysis_date: :desc) }

  def self.for_date(account_id:, date:)
    where(account_id: account_id, analysis_date: date).first
  end
end
