class IncomeSource < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true

  validates :name, presence: true
  validates :expected_day_from, numericality: { in: 1..31 }
  validates :expected_day_to,   numericality: { in: 1..31 }
  validates :expected_amount,   numericality: { greater_than: 0 }
  validate  :day_range_valid

  scope :active, -> { where(active: true).order(:expected_day_from) }

  private

  def day_range_valid
    return unless expected_day_from && expected_day_to
    errors.add(:expected_day_to, "debe ser >= expected_day_from") if expected_day_to < expected_day_from
  end
end
