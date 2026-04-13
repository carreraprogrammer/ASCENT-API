class TelegramUpdate < ApplicationRecord
  validates :update_id,   presence: true, uniqueness: true
  validates :update_type, presence: true
  validates :payload,     presence: true

  scope :unconsumed, -> { where(consumed: false).order(:update_id) }

  def self.store!(update_id:, update_type:, payload:)
    create!(update_id: update_id, update_type: update_type, payload: payload)
  rescue ActiveRecord::RecordNotUnique
    # ya existe — idempotente
    nil
  end
end
