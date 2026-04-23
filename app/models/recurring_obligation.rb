class RecurringObligation < ApplicationRecord
  include AccountScopedFromUser

  SOURCE_TYPES = %w[Debt Investment].freeze
  DEBT_SOURCE_TYPE = "Debt".freeze

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :category, optional: true
  belongs_to :subcategory, optional: true
  belongs_to :source, polymorphic: true, optional: true

  # Una obligación puede estar "destinada" a una deuda o meta de ahorro.
  # Cuando el destino se liquida (paid_off / achieved), esta obligación
  # se desactiva automáticamente via callback en el modelo destino.
  belongs_to :allocatable, polymorphic: true, optional: true

  BUDGET_CATEGORIES = %w[
    housing utilities groceries transportation health
    debt_payoff dining_leisure personal_care savings_buffer
  ].freeze

  validates :name,   presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :due_day, numericality: { in: 1..31 }, allow_nil: true
  validates :budget_category, inclusion: { in: BUDGET_CATEGORIES }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  scope :active, -> { where(active: true).order(:due_day) }

  before_validation :synchronize_source_references

  validate :source_reference_must_be_complete
  validate :source_reference_cannot_conflict_with_allocatable
  validate :debt_source_must_exist

  # Agrega una observación de la IA al historial (nunca sobreescribe).
  def add_ai_observation(text)
    observations = (ai_analysis || []) + [ { "date" => Date.today.iso8601, "text" => text } ]
    update!(ai_analysis: observations)
  end

  def debt_source?
    source_type == DEBT_SOURCE_TYPE || allocatable_type == DEBT_SOURCE_TYPE
  end

  private

  def synchronize_source_references
    if clearing_source_reference? && allocatable_type.in?(SOURCE_TYPES) && allocatable_id.present?
      self.allocatable_type = nil
      self.allocatable_id = nil
    end

    if clearing_allocatable_reference? && source_type.in?(SOURCE_TYPES) && source_id.present?
      self.source_type = nil
      self.source_id = nil
    end

    if source_type.blank? && source_id.blank? && allocatable_type.in?(SOURCE_TYPES) && allocatable_id.present?
      self.source_type = allocatable_type
      self.source_id = allocatable_id
    end

    if allocatable_type.blank? && allocatable_id.blank? && source_type.in?(SOURCE_TYPES) && source_id.present?
      self.allocatable_type = source_type
      self.allocatable_id = source_id
    end
  end

  def source_reference_must_be_complete
    source_fields_present = source_type.present? || source_id.present?
    allocatable_fields_present = allocatable_type.present? || allocatable_id.present?

    if source_fields_present && (source_type.blank? || source_id.blank?)
      errors.add(:base, "source_type and source_id must be provided together")
    end

    if allocatable_fields_present && (allocatable_type.blank? || allocatable_id.blank?)
      errors.add(:base, "allocatable_type and allocatable_id must be provided together")
    end
  end

  def source_reference_cannot_conflict_with_allocatable
    return if source_type.blank? || source_id.blank?
    return if allocatable_type.blank? || allocatable_id.blank?
    return if source_type == allocatable_type && source_id == allocatable_id

    errors.add(:base, "source reference conflicts with allocatable reference")
  end

  def debt_source_must_exist
    return unless source_type == DEBT_SOURCE_TYPE && source_id.present?
    return if Debt.exists?(id: source_id)

    errors.add(:source_id, "must reference an existing debt")
  end

  def clearing_source_reference?
    source_type.blank? && source_id.blank? && (will_save_change_to_source_type? || will_save_change_to_source_id?)
  end

  def clearing_allocatable_reference?
    allocatable_type.blank? && allocatable_id.blank? && (will_save_change_to_allocatable_type? || will_save_change_to_allocatable_id?)
  end
end
