class ErrorReport < ApplicationRecord
  STATUSES = %w[pending in_progress resolved ignored].freeze

  validates :error_hash,      presence: true
  validates :exception_class, presence: true
  validates :message,         presence: true
  validates :stacktrace,      presence: true
  validates :status,          inclusion: { in: STATUSES }

  scope :active,   -> { where(status: %w[pending in_progress]) }
  scope :pending,  -> { where(status: "pending") }

  def self.record!(exception, endpoint:, http_method:, params:)
    hash     = compute_hash(exception)
    now      = Time.current

    record = find_or_initialize_by(error_hash: hash)

    if record.new_record?
      record.assign_attributes(
        exception_class: exception.class.name,
        message:         exception.message.truncate(500),
        stacktrace:      (exception.backtrace || []).first(20).join("\n"),
        endpoint:        endpoint,
        http_method:     http_method,
        params:          params,
        first_seen_at:   now,
        last_seen_at:    now
      )
      record.save!
      :new
    else
      record.increment!(:occurrence_count)
      record.update_column(:last_seen_at, now)
      :duplicate
    end
  end

  def self.compute_hash(exception)
    top = (exception.backtrace || []).first(3).join("|")
    Digest::SHA256.hexdigest("#{exception.class.name}|#{top}")[0, 16]
  end
end
