class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :resource, presence: true, uniqueness: { scope: :action }
  validates :action, presence: true

  scope :for_resource, ->(resource) { where(resource: resource) }
end
