class SavingsGoalAdjustment < ApplicationRecord
  belongs_to :savings_goal
  belongs_to :account
  belongs_to :user

  validates :date, :description, :key, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :key, uniqueness: { scope: :savings_goal_id }
end
