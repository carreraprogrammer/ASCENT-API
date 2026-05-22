class WebChatJob < ApplicationJob
  BRAIN_URL   = ENV.fetch("AGENT_BRAIN_URL", "https://daniel15k-agents-production.up.railway.app")
  BRAIN_TOKEN = ENV.fetch("DANIEL15K_SERVICE_TOKEN", "")
  HISTORY_TURNS = 8

  def perform(account_id:, session_id:, message: nil, event_response: nil)
    # Read prior context BEFORE saving current message so it doesn't appear twice
    prior_messages = ChatMessage
      .where(account_id: account_id, channel: "app")
      .order(created_at: :asc)
      .last(HISTORY_TURNS * 2)
      .map { |m| { role: m.role, content: m.content } }

    # Persist the user message so the agent can save its response against the same account
    if message.present?
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
      prior_messages: prior_messages.presence
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
