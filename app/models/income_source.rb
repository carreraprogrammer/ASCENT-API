class IncomeSource < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true
  has_many :schedules, class_name: "IncomeSourceSchedule", dependent: :destroy
  has_many :transactions, dependent: :nullify

  CLASSIFICATIONS = %w[base variable seasonal one_time].freeze
  CADENCES = %w[monthly biweekly weekly irregular].freeze

  validates :name, presence: true
  validates :expected_day_from, numericality: { in: 1..31 }
  validates :expected_day_to,   numericality: { in: 1..31 }
  validates :expected_amount,   numericality: { greater_than: 0 }
  validates :classification, inclusion: { in: CLASSIFICATIONS }, allow_nil: true
  validates :cadence, inclusion: { in: CADENCES }, allow_nil: true
  validates :reliability_score, numericality: { in: 0..100 }, allow_nil: true
  validate  :day_range_valid

  scope :active, -> { where(active: true).order(:expected_day_from) }

  def sync_from_schedules!
    rows = schedules.to_a
    return if rows.empty?

    self.expected_day_from = rows.map(&:expected_day_from).min
    self.expected_day_to = rows.map(&:expected_day_to).max
    self.expected_amount = rows.sum(&:expected_amount)
  end

  private

  def day_range_valid
    return unless expected_day_from && expected_day_to
    errors.add(:expected_day_to, "debe ser >= expected_day_from") if expected_day_to < expected_day_from
  end
end
