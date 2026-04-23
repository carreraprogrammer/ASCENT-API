class Account < ApplicationRecord
  belongs_to :owner_user, class_name: "User"

  has_many :transactions, dependent: :nullify
  has_many :debts, dependent: :nullify
  has_many :budgets, dependent: :nullify
  has_many :monthly_financial_plans, dependent: :nullify
  has_many :income_sources, dependent: :nullify
  has_many :recurring_obligations, dependent: :nullify
  has_many :planned_expenses, dependent: :nullify
  has_many :pending_actions, dependent: :nullify
  has_many :financial_contexts, dependent: :nullify
  has_many :categories, dependent: :nullify
  has_many :delegations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
end
