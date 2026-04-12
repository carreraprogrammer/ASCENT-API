class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
end
