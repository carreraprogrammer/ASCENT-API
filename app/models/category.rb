class Category < ApplicationRecord
  belongs_to :user, optional: true
  has_many :subcategories, dependent: :destroy
  has_many :transactions, dependent: :nullify

  TYPES = %w[committed necessary discretionary investment social income unknown].freeze

  validates :name, presence: true
  validates :code, presence: true
  validates :category_type, presence: true, inclusion: { in: TYPES }
end
