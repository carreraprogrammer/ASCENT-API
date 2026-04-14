class Debt < ApplicationRecord
  belongs_to :user

  TYPES    = %w[credit_card personal_loan family mortgage].freeze
  STATUSES = %w[active paid_off paused].freeze

  validates :name,            presence: true
  validates :debt_type,       inclusion: { in: TYPES }
  validates :status,          inclusion: { in: STATUSES }
  validates :current_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :monthly_payment, numericality: { greater_than_or_equal_to: 0 }

  before_save :auto_paid_off

  scope :active, -> { where(status: "active") }

  private

  def auto_paid_off
    self.status = "paid_off" if current_balance <= 0 && status == "active"
  end
end
