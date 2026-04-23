class Debt < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true

  # Una deuda puede tener una sola obligación recurrente asociada
  # (la cuota mensual que sale del flujo de caja).
  # Cuando la deuda se paga, la obligación se desactiva automáticamente.
  has_one :recurring_obligation, as: :allocatable

  TYPES    = %w[credit_card personal_loan family mortgage].freeze
  STATUSES = %w[active paid_off paused disputed].freeze

  validates :name,            presence: true
  validates :debt_type,       inclusion: { in: TYPES }
  validates :status,          inclusion: { in: STATUSES }
  validates :current_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :monthly_payment, numericality: { greater_than_or_equal_to: 0 }

  before_save  :auto_paid_off
  after_update :deactivate_obligation_if_resolved

  scope :active,    -> { where(status: "active") }
  scope :disputed,  -> { where(status: "disputed") }

  # Agrega una observación de la IA al historial (nunca sobreescribe).
  def add_ai_observation(text)
    observations = (ai_analysis || []) + [ { "date" => Date.today.iso8601, "text" => text } ]
    update_column(:ai_analysis, observations)
  end

  private

  def auto_paid_off
    self.status = "paid_off" if current_balance <= 0 && status == "active"
  end

  # Cuando la deuda se liquida o entra en disputa, desactiva la obligación
  # recurrente vinculada para que deje de aparecer en el flujo de caja.
  def deactivate_obligation_if_resolved
    return unless saved_change_to_status?
    return unless %w[paid_off disputed].include?(status)

    RecurringObligation
      .where(
        "(allocatable_type = :type AND allocatable_id = :id) OR (source_type = :type AND source_id = :id)",
        type: "Debt",
        id: id
      )
      .find_each { |obligation| obligation.update(active: false) }
  end
end
