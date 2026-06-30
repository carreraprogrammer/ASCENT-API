class BudgetCategory < ApplicationRecord
  belongs_to :account

  SYSTEM_CODES = %w[
    housing utilities groceries transportation health
    debt_payoff dining_out personal_care savings_emergency
  ].freeze

  # RFC-0001: `flexible` aceptado (expand). `discretionary`/`investment` siguen hasta Etapa 5.
  CATEGORY_TYPES = %w[committed necessary discretionary flexible investment].freeze

  validates :code, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :category_type, inclusion: { in: CATEGORY_TYPES }

  scope :active, -> { where(active: true).order(:sort_order) }
  scope :system_categories, -> { where(system: true) }
end
