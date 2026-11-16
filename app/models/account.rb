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
  has_one :account_progress, dependent: :destroy
  has_many :feature_flags, dependent: :destroy
  has_many :xp_events, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  # ASC-4 fase 6: la cuenta demo (datos ficticios) queda fuera de agentes programados, consolidados y avisos.
  scope :not_demo, -> { joins(:owner_user).where(users: { demo: false }) }
end
