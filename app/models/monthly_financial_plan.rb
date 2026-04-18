class MonthlyFinancialPlan < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true

  STATUSES = %w[draft provisional confirmed superseded].freeze
  MODES = %w[conservative expected].freeze
  OVERFLOW_RULES = %w[debt emergency_fund investment mixed].freeze

  validates :month, inclusion: { in: 1..12 }
  validates :year, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }
  validates :overflow_rule, inclusion: { in: OVERFLOW_RULES }
  validates :base_budget_income, :expected_variable_income,
            :recurring_obligations_total, :debt_minimums_total,
            :protected_buffer_amount, :discretionary_limit,
            numericality: { greater_than_or_equal_to: 0 }
  validates :investment_target, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reward_pct, numericality: { in: 1..100 }, allow_nil: true
  validates :account_id, uniqueness: { scope: [ :year, :month ] }
end
