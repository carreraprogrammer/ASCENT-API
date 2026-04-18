class WebChatJob < ApplicationJob
  BRAIN_URL = ENV.fetch("AGENT_BRAIN_URL", "https://daniel15k-agents-production.up.railway.app")
  BRAIN_TOKEN = ENV.fetch("DANIEL15K_SERVICE_TOKEN", "")
  API_BASE_URL = ENV.fetch("DANIEL15K_API_URL", "http://localhost:3000")

  def perform(account_id:, session_id:, message: nil, event_response: nil)
    budget_context = fetch_budget_context(account_id)

    body = {
      account_id: account_id,
      session_id: session_id,
      message: message,
      event_response: event_response,
      budget_context: budget_context,
    }.compact.to_json

    uri = URI("#{BRAIN_URL}/agents/web_chat")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{BRAIN_TOKEN}"
    request.body = body

    response = http.request(request)
    Rails.logger.info("[WebChatJob] Brain responded #{response.code} for session #{session_id}")
  rescue => e
    Rails.logger.error("[WebChatJob] Failed for session #{session_id}: #{e.message}")
    raise
  end

  private

  def fetch_budget_context(account_id)
    uri = URI("#{API_BASE_URL}/api/v1/budget_context")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{BRAIN_TOKEN}"
    request["X-Account-Id"] = account_id.to_s
    request["X-Agent-Type"] = "finance_coach"

    response = http.request(request)

    if response.code.to_i == 200
      parsed = JSON.parse(response.body)
      parsed["data"]
    else
      Rails.logger.warn("[WebChatJob] budget_context fetch returned #{response.code} for account #{account_id}")
      nil
    end
  rescue => e
    Rails.logger.warn("[WebChatJob] budget_context fetch failed for account #{account_id}: #{e.message}")
    nil
  end
end
