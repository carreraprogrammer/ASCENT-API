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

  # true cuando el refresh token murió y el usuario debe reconectar Gmail.
  def needs_reconnect?
    reconnect_required_at.present?
  end

  # Devuelve la lista de remitentes bancarios como array Ruby.
  # nil / vacío = sin configurar (el agente usará búsqueda por keywords).
  def bank_senders_list
    return [] if bank_senders.blank?
    JSON.parse(bank_senders)
  rescue JSON::ParserError
    []
  end
end
