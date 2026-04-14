class RecurringObligation < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true

  # Una obligación puede estar "destinada" a una deuda o meta de ahorro.
  # Cuando el destino se liquida (paid_off / achieved), esta obligación
  # se desactiva automáticamente via callback en el modelo destino.
  belongs_to :allocatable, polymorphic: true, optional: true

  validates :name,   presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :due_day, numericality: { in: 1..31 }, allow_nil: true

  scope :active, -> { where(active: true).order(:due_day) }

  # Agrega una observación de la IA al historial (nunca sobreescribe).
  def add_ai_observation(text)
    observations = (ai_analysis || []) + [ { "date" => Date.today.iso8601, "text" => text } ]
    update!(ai_analysis: observations)
  end
end
