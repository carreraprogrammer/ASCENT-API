class XpEvent < ApplicationRecord
  belongs_to :account

  validates :action_type, presence: true
  validates :xp_amount, numericality: { other_than: 0 }
end
