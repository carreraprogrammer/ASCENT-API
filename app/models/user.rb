class User < ApplicationRecord
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :permissions, through: :roles

  validates :email, presence: true, uniqueness: true
  validates :encrypted_password, presence: true, unless: :oauth_user?
  validates :name, presence: true

  def oauth_user?
    auth_provider.present?
  end
end
