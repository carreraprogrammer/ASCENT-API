class Subcategory < ApplicationRecord
  belongs_to :category
  has_many :transactions, dependent: :nullify

  validates :name, presence: true
  validates :code, presence: true
end
