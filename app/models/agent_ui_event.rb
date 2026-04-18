class AgentUiEvent < ApplicationRecord
  belongs_to :account

  EVENT_TYPES = %w[
    show_plan_proposal
    show_card
    show_form
    request_confirmation
    navigate
  ].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :payload, presence: true

  scope :pending,   -> { where(consumed_at: nil) }
  scope :consumed,  -> { where.not(consumed_at: nil) }
  scope :for_session, ->(sid) { where(session_id: sid) if sid.present? }

  def consume!
    update!(consumed_at: Time.current)
  end
end
