class Delegation < ApplicationRecord
  belongs_to :user
  belongs_to :account
  belongs_to :service_account
  belongs_to :agent_type

  validates :scopes, presence: true

  scope :active, -> { where(active: true) }

  def allows_scope?(scope)
    Array(scopes).include?(scope.to_s)
  end
end
