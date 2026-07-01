class Subcategory < ApplicationRecord
  # RFC-0001: la subcategoría es una FUNCIÓN ortogonal al tier (categoría). `category_id`
  # es el tier primario/default; una función puede pertenecer a VARIAS categorías (tiers)
  # vía la tabla join (many-to-many). El tier de una transacción lo da su category_id.
  belongs_to :category, optional: true
  belongs_to :user, optional: true
  has_many :transactions, dependent: :nullify
  has_many :planned_expenses, dependent: :restrict_with_exception
  has_many :category_subcategories, dependent: :destroy
  has_many :linked_categories, through: :category_subcategories, source: :category

  validates :name, presence: true
  validates :code, presence: true
end
