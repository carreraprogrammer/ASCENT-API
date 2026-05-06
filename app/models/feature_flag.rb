class FeatureFlag < ApplicationRecord
  belongs_to :account

  STATUSES = %w[locked available_to_unlock active paused needs_context].freeze

  validates :feature_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :feature_key, uniqueness: { scope: :account_id }
end
