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
  belongs_to :savings_goal, optional: true

  TYPES = %w[expense income].freeze
  SOURCES = %w[telegram gmail manual brain].freeze
  STATUSES = %w[confirmed pending].freeze
  PAYMENT_SOURCES = %w[credit_card debit cash].freeze
  CREDIT_CARD_STATUSES = %w[pending settled].freeze
  # RFC-0001 — tags ortogonales al tier de agencia. `social` reemplaza la vieja categoría
  # social; `time_saving` reservado (research brief). Ver Rediseño.md.
  TAGS = %w[social time_saving].freeze

  # Transacciones que llevan un tag dado (jsonb containment, usa índice GIN).
  scope :tagged, ->(tag) { where("tags @> ?", [ tag ].to_json) }

  validates :date, presence: true
  validates :concept, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, inclusion: { in: TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :year, presence: true
  validates :month, presence: true
  validates :source_event_id, uniqueness: { scope: [ :account_id, :source ], allow_nil: true }, if: -> { source_event_id.present? }
  validates :payment_source, inclusion: { in: PAYMENT_SOURCES }, allow_nil: true
  validates :credit_card_status, inclusion: { in: CREDIT_CARD_STATUSES }, allow_nil: true
  validate :tags_must_be_known

  private

  def tags_must_be_known
    return if tags.blank?

    unknown = Array(tags) - TAGS
    errors.add(:tags, "contiene etiquetas no válidas: #{unknown.join(', ')}") if unknown.any?
  end
end
