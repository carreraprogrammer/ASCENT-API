# Ajuste de conciliación del saldo. Solo afecta el saldo acumulado ("disponible real"),
# nunca ingresos, gastos ni estadísticas. amount lleva signo.
class BalanceAdjustment < ApplicationRecord
  belongs_to :account

  validates :date, :description, presence: true
  validates :amount, numericality: { other_than: 0 }
end
