class CategorySubcategory < ApplicationRecord
  belongs_to :category
  belongs_to :subcategory

  validates :category_id, uniqueness: { scope: :subcategory_id }
end
