class AccountProgress < ApplicationRecord
  belongs_to :account

  LEVELS = [0, 1, 2, 3, 4, 5].freeze
  MAX_LEVEL = 5

  validates :xp, numericality: { greater_than_or_equal_to: 0 }
  validates :level, inclusion: { in: LEVELS }
  validates :readiness_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end
