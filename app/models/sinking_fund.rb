class SinkingFund < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true

  validates :name, presence: true
  validates :monthly_contribution, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
end
