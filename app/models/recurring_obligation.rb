class RecurringObligation < ApplicationRecord
  include AccountScopedFromUser

  SOURCE_TYPES    = %w[Debt Investment].freeze
  DEBT_SOURCE_TYPE = "Debt".freeze

  belongs_to :user
  belongs_to :account,     optional: true
  belongs_to :category,    optional: true
  belongs_to :subcategory, optional: true
  belongs_to :source, polymorphic: true, optional: true

  BUDGET_CATEGORIES = %w[
    housing utilities groceries transportation health
    debt_payoff dining_leisure personal_care savings_buffer
  ].freeze

  validates :name,   presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :due_day, numericality: { in: 1..31 }, allow_nil: true
  validates :budget_category, inclusion: { in: BUDGET_CATEGORIES }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  validate :source_reference_must_be_complete
  validate :debt_source_must_exist
  validate :debt_source_must_use_credit_subcategory

  scope :active, -> { where(active: true).order(:due_day) }

  def debt_source?
    source_type == DEBT_SOURCE_TYPE
  end

  def add_ai_observation(text)
    observations = (ai_analysis || []) + [ { "date" => Date.today.iso8601, "text" => text } ]
    update!(ai_analysis: observations)
  end

  private

  def source_reference_must_be_complete
    return if source_type.blank? && source_id.blank?

    if source_type.blank? || source_id.blank?
      errors.add(:base, "source_type and source_id must be provided together")
    end
  end

  def debt_source_must_exist
    return unless source_type == DEBT_SOURCE_TYPE && source_id.present?
    return if Debt.exists?(id: source_id)

    errors.add(:source_id, "must reference an existing debt")
  end

  def debt_source_must_use_credit_subcategory
    return unless source_type == DEBT_SOURCE_TYPE && source_id.present?
    return if subcategory&.code == "creditos"

    errors.add(:base, "debt links require the 'Créditos' subcategory")
  end
end
