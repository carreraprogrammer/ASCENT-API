class UserMilestone < ApplicationRecord
  VALID_CODES = %w[
    first_transaction
    first_income_source
    first_recurring_obligation
    first_debt_registered
    first_strategy_set
    first_monthly_plan
    first_debt_paid_off
    three_months_planned
    first_sinking_fund
    income_diversified
    emergency_fund_reached
    debt_free
    debt_paid_off
    extra_debt_payment
    new_debt_acquired
    payment_missed
    emergency_fund_tranche
    investment_started
    investment_streak
    savings_goal_tranche
    discretionary_under_budget
    overflow_deployed
    month_positive_balance
    discretionary_over_budget
    emergency_fund_withdrawn
    investment_withdrawn
    plan_not_confirmed
    level_2_unlocked
    level_3_unlocked
    level_4_unlocked
    level_5_unlocked
  ].freeze

  belongs_to :user
  belongs_to :account, optional: true

  validates :code, inclusion: { in: VALID_CODES }
end
