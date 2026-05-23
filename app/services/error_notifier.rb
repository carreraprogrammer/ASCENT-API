require "net/http"
require "json"
require "digest"

class ErrorNotifier
  FILTERED_PARAMS = %w[password token secret authorization credit_card].freeze
  IGNORED_PATHS   = %w[/health /api-docs].freeze

  def self.capture(exception, env)
    return if ignored?(env)

    endpoint   = env["PATH_INFO"]
    http_method = env["REQUEST_METHOD"]
    params     = filtered_params(env)

    result = ErrorReport.record!(
      exception,
      endpoint:    endpoint,
      http_method: http_method,
      params:      params
    )

    return unless result == :new

    notify_agents_async(exception, endpoint, http_method, ErrorReport.find_by(
      error_hash: ErrorReport.compute_hash(exception)
    ))
  rescue => e
    Rails.logger.error("[ErrorNotifier] Failed to capture error: #{e.message}")
  end

  def self.ignored?(env)
    path = env["PATH_INFO"].to_s
    IGNORED_PATHS.any? { |p| path.start_with?(p) }
  end

  def self.filtered_params(env)
    raw = env["action_dispatch.request.parameters"] ||
          Rack::Utils.parse_nested_query(env["QUERY_STRING"].to_s)

    deep_filter(raw)
  rescue
    {}
  end

  def self.deep_filter(hash)
    return hash unless hash.is_a?(Hash)

    hash.each_with_object({}) do |(k, v), acc|
      acc[k] = if FILTERED_PARAMS.any? { |f| k.to_s.downcase.include?(f) }
                 "[FILTERED]"
               elsif v.is_a?(Hash)
                 deep_filter(v)
               else
                 v
               end
    end
  end

  def self.notify_agents_async(exception, endpoint, http_method, report)
    webhook_url = ENV["AGENTS_ERROR_WEBHOOK_URL"]
    return unless webhook_url.present?

    payload = {
      error_id:        report.id,
      error_hash:      report.error_hash,
      exception_class: exception.class.name,
      message:         exception.message.truncate(500),
      stacktrace:      (exception.backtrace || []).first(20),
      endpoint:        endpoint,
      http_method:     http_method,
      params:          report.params,
      occurred_at:     Time.current.iso8601
    }

    Thread.new do
      uri  = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      req = Net::HTTP::Post.new(uri.path, {
        "Content-Type" => "application/json",
        "X-Webhook-Secret" => ENV.fetch("AGENTS_WEBHOOK_SECRET", "")
      })
      req.body = payload.to_json

      http.request(req)
    rescue => e
      Rails.logger.error("[ErrorNotifier] Webhook delivery failed: #{e.message}")
    end
  end
end
