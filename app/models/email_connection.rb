class EmailConnection < ApplicationRecord
  belongs_to :account

  encrypts :access_token_ciphertext,  deterministic: false
  encrypts :refresh_token_ciphertext, deterministic: false

  PROVIDERS = %w[gmail].freeze
  validates :provider, inclusion: { in: PROVIDERS }

  # Alias legible para el resto de la app
  alias_attribute :access_token,  :access_token_ciphertext
  alias_attribute :refresh_token, :refresh_token_ciphertext

  def expired?
    expires_at.present? && expires_at <= Time.current + 5.minutes
  end
end
