# config/initializers/rack_attack.rb
#
# Rate limiting para la API. Usa el memory store de Rails (suficiente para un
# solo proceso Puma con 10 usuarios). Si en el futuro se agrega Redis, cambiar
# Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])
#
# Límites activos:
#
#   auth/login + auth/register   5 req/min por IP  — evita credential stuffing
#   agents/chat                 10 req/min por account_id — el canal principal
#   agents/* (preflight, etc.)  30 req/min por account_id
#   nightly writes (NightAnalysis, AgentInsight, AgentUiEvents)
#                               20 req/min por account_id
#   API general                120 req/min por IP  — capa de seguridad base

class Rack::Attack
  # ── Cache store ────────────────────────────────────────────────────────────
  # Rails.cache es memory store por defecto (un proceso Puma → coherente).
  # Para multi-proceso agregar Redis y descomentar la línea de abajo.
  Rack::Attack.cache.store = Rails.cache

  # ── Helpers ────────────────────────────────────────────────────────────────

  # Extrae account_id del header X-Account-Id o del parámetro account_id.
  # Devuelve nil si no está presente (throttle por IP como fallback).
  def self.account_id_from(req)
    req.env["HTTP_X_ACCOUNT_ID"].presence || req.params["account_id"].presence
  end

  # Clave de throttle: por account_id si está disponible, si no por IP.
  def self.account_or_ip(req)
    account_id = account_id_from(req)
    account_id ? "account:#{account_id}" : "ip:#{req.ip}"
  end

  # ── Safelist — siempre permitido ────────────────────────────────────────────

  # Health checks de Railway (keep-alive del agente, load balancer)
  safelist("allow health checks") do |req|
    req.path == "/up" || req.path == "/health"
  end

  # ── Throttles ──────────────────────────────────────────────────────────────

  # 1. Auth: login y registro — 5 intentos/minuto por IP
  throttle("auth/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{\A/api/v1/auth/(login|register)\z}) && req.post?
  end

  # 2. Chat del agente — 10 mensajes/minuto por account_id
  #    Canal principal del usuario con el agente: límite generoso pero acotado.
  throttle("agents/chat", limit: 10, period: 1.minute) do |req|
    account_or_ip(req) if req.path == "/api/v1/agents/chat" && req.post?
  end

  # 3. Endpoints del agente (preflight, nightly writes, insights)
  #    30 req/minuto por account_id — el agente nocturno hace ~15 llamadas por noche.
  AGENT_WRITE_PATHS = %w[
    /api/v1/agents/preflight
    /api/v1/night_analyses
    /api/v1/agent_events
  ].freeze

  throttle("agents/write", limit: 30, period: 1.minute) do |req|
    account_or_ip(req) if AGENT_WRITE_PATHS.any? { |p| req.path.start_with?(p) }
  end

  # 4. Capa base — 120 req/minuto por IP
  #    Protege contra scraping o loops con bug de un cliente.
  throttle("api/ip", limit: 120, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # ── Respuesta 429 ──────────────────────────────────────────────────────────

  self.throttled_responder = lambda do |env|
    req         = ActionDispatch::Request.new(env)
    match_data  = env["rack.attack.match_data"] || {}
    period      = match_data[:period] || 60
    limit       = match_data[:limit]  || "?"
    retry_after = (match_data[:epoch_time].to_i + period - Time.now.to_i).clamp(1, period)

    body = {
      errors: [
        {
          status: "429",
          code:   "rate_limit_exceeded",
          detail: "Demasiadas solicitudes. Límite: #{limit} por #{period}s. " \
                  "Reintentá en #{retry_after}s.",
          source: { pointer: req.path }
        }
      ]
    }.to_json

    [
      429,
      {
        "Content-Type"  => "application/json",
        "Retry-After"   => retry_after.to_s,
        "X-RateLimit-Limit"     => limit.to_s,
        "X-RateLimit-RetryAfter" => retry_after.to_s,
      },
      [ body ]
    ]
  end
end
