class IncomeSourceSchedule < ApplicationRecord
  belongs_to :income_source

  validates :ordinal, numericality: { greater_than: 0 }
  validates :expected_day_from, numericality: { in: 1..31 }
  validates :expected_day_to, numericality: { in: 1..31 }
  validates :expected_amount, numericality: { greater_than: 0 }
  validate :day_range_valid

  default_scope { order(:ordinal, :expected_day_from) }

  private

  def day_range_valid
    return unless expected_day_from && expected_day_to

    errors.add(:expected_day_to, "debe ser >= expected_day_from") if expected_day_to < expected_day_from
  end
end
