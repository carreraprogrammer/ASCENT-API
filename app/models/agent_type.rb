class AgentType < ApplicationRecord
  has_many :delegations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
end
