class AgentInsight < ApplicationRecord
  belongs_to :account
  belongs_to :insightable, polymorphic: true

  KINDS    = %w[tip congratulation alert proposal achievement].freeze
  STATUSES = %w[new seen actioned dismissed].freeze

  validates :insight_kind, inclusion: { in: KINDS }
  validates :status,       inclusion: { in: STATUSES }
  validates :title,        presence: true
  validates :body,         presence: true
  validates :generated_at, presence: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :visible,     -> { where.not(status: "dismissed") }
  scope :latest,      -> { order(generated_at: :desc) }

  def self.latest_for(account_id:)
    for_account(account_id).visible.latest.first
  end
end
