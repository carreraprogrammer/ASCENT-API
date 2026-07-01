class Subcategory < ApplicationRecord
  # RFC-0001: la subcategoría es una FUNCIÓN ortogonal al tier (categoría). Puede no
  # pertenecer a una categoría fija; el tier de una transacción lo da su category_id.
  belongs_to :category, optional: true
  belongs_to :user, optional: true
  has_many :transactions, dependent: :nullify
  has_many :planned_expenses, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :code, presence: true
end
