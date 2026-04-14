class FinancialContext < ApplicationRecord
  belongs_to :user

  PHASES     = %w[debt_payoff emergency_fund investing wealth_building].freeze
  STRATEGIES = %w[snowball avalanche].freeze

  validates :phase,    inclusion: { in: PHASES }
  validates :strategy, inclusion: { in: STRATEGIES }
  validates :monthly_income_1, numericality: { greater_than_or_equal_to: 0 }
  validates :monthly_income_2, numericality: { greater_than_or_equal_to: 0 }
  validates :reward_pct, numericality: { in: 1..100 }
end
