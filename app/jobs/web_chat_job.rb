class WebChatJob < ApplicationJob
  BRAIN_URL   = ENV.fetch("AGENT_BRAIN_URL", "https://daniel15k-agents-production.up.railway.app")
  BRAIN_TOKEN = ENV.fetch("DANIEL15K_SERVICE_TOKEN", "")
  HISTORY_TURNS = 8

  def perform(account_id:, session_id:, message: nil, event_response: nil, skip_history: false)
    prior_messages = if skip_history
      []
    else
      # Read prior context BEFORE saving current message so it doesn't appear twice
      ChatMessage
        .where(account_id: account_id, channel: "app")
        .order(created_at: :asc)
        .last(HISTORY_TURNS * 2)
        .map { |m| { role: m.role, content: m.content } }
    end

    # Persist the user message only for persistent chat, not shortcut captures
    if message.present? && !skip_history
      ChatMessage.create!(
        account_id: account_id,
        channel:    "app",
        role:       "user",
        content:    message
      )
    end

    body = {
      account_id:     account_id,
      session_id:     session_id,
      message:        message,
      event_response: event_response,
      prior_messages: prior_messages.presence,
      skip_history:   skip_history,
    }.compact.to_json

    uri  = URI("#{BRAIN_URL}/agents/app_chat")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 60

    request                  = Net::HTTP::Post.new(uri.path)
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{BRAIN_TOKEN}"
    request.body             = body

    response = http.request(request)
    Rails.logger.info("[WebChatJob] Brain responded #{response.code} for session #{session_id}")
  rescue => e
    Rails.logger.error("[WebChatJob] Failed for session #{session_id}: #{e.message}")
    raise
  end
end
