class Budget < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :category
  belongs_to :subcategory, optional: true

  validates :month,        presence: true, inclusion: { in: 1..12 }
  validates :year,         presence: true
  validates :amount_limit, numericality: { greater_than_or_equal_to: 0 }
end
