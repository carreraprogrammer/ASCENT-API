class Subcategory < ApplicationRecord
  belongs_to :category
  belongs_to :user, optional: true
  has_many :transactions, dependent: :nullify

  validates :name, presence: true
  validates :code, presence: true
end
