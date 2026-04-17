class PendingAction < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true

  TYPES    = %w[budget_planning debt_setup onboarding financial_context_setup income_setup].freeze
  STATUSES = %w[in_progress waiting_response completed cancelled expired].freeze

  validates :action_type, inclusion: { in: TYPES }
  validates :status,      inclusion: { in: STATUSES }

  scope :active, -> {
    where(status: %w[in_progress waiting_response])
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }
end
