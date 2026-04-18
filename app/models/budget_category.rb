class BudgetCategory < ApplicationRecord
  belongs_to :account

  SYSTEM_CODES = %w[
    housing utilities groceries transportation health
    debt_payoff dining_out personal_care savings_emergency
  ].freeze

  CATEGORY_TYPES = %w[committed necessary discretionary investment].freeze

  validates :code, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :category_type, inclusion: { in: CATEGORY_TYPES }

  scope :active, -> { where(active: true).order(:sort_order) }
  scope :system_categories, -> { where(system: true) }
end
