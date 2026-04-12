class FormSchema < ApplicationRecord
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9\-]+\z/, message: "only lowercase letters, numbers, hyphens" }
  validates :title, presence: true
  validates :submit_endpoint, presence: true
  validates :submit_method, inclusion: { in: %w[POST PUT PATCH] }
  validates :fields, presence: true
end
