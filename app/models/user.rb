class User < ApplicationRecord
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :permissions, through: :roles
  has_many :owned_accounts, class_name: "Account", foreign_key: :owner_user_id, dependent: :destroy
  has_many :delegations, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :encrypted_password, presence: true, unless: :oauth_user?
  validates :name, presence: true

  after_create :ensure_default_account!

  def oauth_user?
    auth_provider.present?
  end

  def default_account
    owned_accounts.first || ensure_default_account!
  end

  def ensure_default_account!
    owned_accounts.find_or_create_by!(slug: "account-user-#{id}") do |account|
      account.name = name.presence || email
      account.active = true
    end
  end
end
