class FinancialContext < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true

  PHASES     = %w[debt_payoff emergency_fund investing wealth_building].freeze
  STRATEGIES = %w[snowball avalanche].freeze

  validates :phase,     inclusion: { in: PHASES }
  validates :strategy,  inclusion: { in: STRATEGIES }
  validates :reward_pct, numericality: { in: 1..100 }
end
