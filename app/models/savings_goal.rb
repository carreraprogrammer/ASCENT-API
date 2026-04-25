class SavingsGoal < ApplicationRecord
  belongs_to :user
  belongs_to :account

  STATUSES = %w[active paused completed].freeze

  validates :name, presence: true
  validates :target_amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  before_save :calculate_monthly_contribution_needed

  private

  def calculate_monthly_contribution_needed
    if target_date.present?
      remaining = target_amount.to_i - current_amount.to_i
      months = ((target_date - Date.today) / 30.0).ceil
      self.monthly_contribution_needed = months.positive? ? (remaining.to_f / months).ceil : remaining
    else
      self.monthly_contribution_needed = nil
    end
  end
end
