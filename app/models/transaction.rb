class Transaction < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :category, optional: true
  belongs_to :subcategory, optional: true

  TYPES = %w[expense income].freeze
  SOURCES = %w[telegram gmail manual].freeze
  STATUSES = %w[confirmed pending].freeze

  validates :date, presence: true
  validates :concept, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, inclusion: { in: TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :year, presence: true
  validates :month, presence: true
  validates :source_event_id, uniqueness: { scope: [:account_id, :source], allow_nil: true }, if: -> { source_event_id.present? }
end
