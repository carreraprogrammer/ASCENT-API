class ChatMessage < ApplicationRecord
  belongs_to :account

  ROLES    = %w[user assistant].freeze
  CHANNELS = %w[app telegram whatsapp].freeze

  validates :role,    inclusion: { in: ROLES }
  validates :channel, inclusion: { in: CHANNELS }
  validates :content, presence: true
end
