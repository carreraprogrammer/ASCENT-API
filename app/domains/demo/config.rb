module Demo
  # ASC-4 fase 6: modo demo. Una cuenta separada con datos ficticios, de solo lectura.
  module Config
    DEFAULT_EMAIL = "demo@ascent.thecyborgway.dev".freeze
    DEFAULT_SESSION_TTL = 7_200 # 2 h, sin refresh token: al vencer se vuelve a pedir "Ver demo".
    USER_NAME = "Alex".freeze

    def self.email = ENV.fetch("DEMO_EMAIL", DEFAULT_EMAIL).to_s.strip.downcase
    def self.session_ttl = ENV.fetch("DEMO_SESSION_TTL", DEFAULT_SESSION_TTL).to_i
  end
end
