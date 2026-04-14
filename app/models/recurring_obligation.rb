class RecurringObligation < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :name,    presence: true
  validates :amount,  numericality: { greater_than: 0 }
  validates :due_day, numericality: { in: 1..31 }

  scope :active, -> { where(active: true).order(:due_day) }
end
