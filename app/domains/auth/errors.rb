module Auth
  module Errors
    class InvalidEmail < StandardError; end
    class WeakPassword < StandardError; end
    class InvalidToken < StandardError; end
    class ExpiredToken < StandardError; end
    class InvalidCredentials < StandardError; end
    class TokenReuse < StandardError; end
  end
end
