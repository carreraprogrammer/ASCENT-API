class SavingsGoal < ApplicationRecord
  belongs_to :user
  belongs_to :account

  STATUSES = %w[active paused completed].freeze

  validates :name, presence: true
  validates :target_amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  before_save  :calculate_monthly_contribution_needed
  after_commit :sync_recurring_obligation, on: %i[create update]

  private

  # Keep one RecurringObligation in sync with this goal so the commitment
  # shows up in all cash-flow metrics (LiquidityProjection, plan generation, etc.).
  # The obligation has no subcategory — its only job is to be counted as a fixed outflow.
  def sync_recurring_obligation
    return unless monthly_contribution_needed.to_i > 0 || status != "active"

    obligation = RecurringObligation.find_or_initialize_by(
      source_type: "SavingsGoal",
      source_id:   id,
      account_id:  account_id
    )

    rounded = round_contribution(monthly_contribution_needed.to_i)

    if status == "active" && rounded > 0
      obligation.assign_attributes(
        user:    user,
        name:    "Aporte a #{name}",
        amount:  rounded,
        active:  true,
        due_day: 1
      )
      obligation.save! if obligation.new_record? || obligation.changed?
    elsif obligation.persisted? && obligation.active?
      obligation.update_column(:active, false)
    end
  end

  def round_contribution(amount)
    ((amount.to_f / 1000).round * 1000).to_i
  end

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
