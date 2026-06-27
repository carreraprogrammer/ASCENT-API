class SinkingFund < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :planned_expense, optional: true
  # Al borrar un bolsillo, sus transacciones sobreviven como gastos pero se
  # desvinculan (sinking_fund_id -> nil). Sin esto, la FK impide el borrado en
  # cascada cuando un plan con bolsillo fondeado se elimina.
  has_many :transactions, dependent: :nullify

  validates :name, presence: true
  validates :monthly_contribution, numericality: { greater_than_or_equal_to: 0 }
  validates :debit_day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 28 }

  scope :active, -> { where(active: true) }
end
