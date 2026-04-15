class ServiceAccount < ApplicationRecord
  has_many :delegations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    active.find_by(token_hash: Digest::SHA256.hexdigest(raw_token))
  end

  def store_raw_token!(raw_token)
    update!(token_hash: Digest::SHA256.hexdigest(raw_token))
  end
end
