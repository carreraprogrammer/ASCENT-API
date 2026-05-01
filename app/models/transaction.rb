class Transaction < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :category, optional: true
  belongs_to :subcategory, optional: true
  belongs_to :debt, optional: true
  belongs_to :recurring_obligation, optional: true
  belongs_to :income_source, optional: true
  belongs_to :sinking_fund, optional: true

  TYPES = %w[expense income].freeze
  SOURCES = %w[telegram gmail manual].freeze
  STATUSES = %w[confirmed pending].freeze
  PAYMENT_SOURCES = %w[credit_card debit cash].freeze
  CREDIT_CARD_STATUSES = %w[pending settled].freeze

  validates :date, presence: true
  validates :concept, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, inclusion: { in: TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :year, presence: true
  validates :month, presence: true
  validates :source_event_id, uniqueness: { scope: [:account_id, :source], allow_nil: true }, if: -> { source_event_id.present? }
  validates :payment_source, inclusion: { in: PAYMENT_SOURCES }, allow_nil: true
  validates :credit_card_status, inclusion: { in: CREDIT_CARD_STATUSES }, allow_nil: true
  validate :credit_card_status_consistency

  private

  def credit_card_status_consistency
    if payment_source == "credit_card" && credit_card_status.nil?
      errors.add(:credit_card_status, "is required when payment_source is credit_card")
    end
    if payment_source != "credit_card" && credit_card_status.present?
      errors.add(:credit_card_status, "must be nil when payment_source is not credit_card")
    end
  end
end
