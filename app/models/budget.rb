class Budget < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :month,        presence: true, inclusion: { in: 1..12 }
  validates :year,         presence: true
  validates :amount_limit, numericality: { greater_than_or_equal_to: 0 }
  validates :category_id,  uniqueness: { scope: [ :user_id, :month, :year ] }
end
