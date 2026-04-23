class Subcategory < ApplicationRecord
  belongs_to :category
  belongs_to :user, optional: true
  has_many :transactions, dependent: :nullify
  has_many :planned_expenses, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :code, presence: true
end
