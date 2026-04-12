class JwtService
  ALGORITHM = "HS256"

  class InvalidToken < StandardError; end
  class ExpiredToken < StandardError; end

  def self.encode_access_token(user_id:, email:, super_admin: false, permissions: nil)
    payload = {
      user_id: user_id,
      email: email,
      super_admin: super_admin,
      permissions: permissions || Authorization::Interactors::FetchUserPermissions.new.call(user_id: user_id),
      jti: SecureRandom.uuid,
      exp: Time.current.to_i + ENV.fetch("JWT_ACCESS_EXPIRY", 900).to_i,
      type: "access"
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.encode_refresh_token
    SecureRandom.urlsafe_base64(64)
  end

  def self.decode_access_token(token)
    decoded = JWT.decode(token, secret, true, algorithm: ALGORITHM).first
    raise InvalidToken unless decoded["type"] == "access"

    decoded.deep_symbolize_keys
  rescue JWT::ExpiredSignature
    raise ExpiredToken
  rescue JWT::DecodeError, NoMethodError
    raise InvalidToken
  end

  class << self
    alias decode decode_access_token
  end

  def self.secret
    ENV.fetch("JWT_SECRET") { raise "JWT_SECRET environment variable is not set" }
  end
end
