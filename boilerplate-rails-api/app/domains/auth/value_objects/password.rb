module Auth
  module ValueObjects
    class Password
      MIN_LENGTH = 8
      REQUIRES_NUMBER = /\d/
      REQUIRES_UPPERCASE = /[A-Z]/
      attr_reader :raw
      def initialize(raw_value)
        errors = []
        errors << "Password must be at least #{MIN_LENGTH} characters" if raw_value.to_s.length < MIN_LENGTH
        errors << "Password must contain at least one number" unless raw_value.to_s.match?(REQUIRES_NUMBER)
        errors << "Password must contain at least one uppercase letter" unless raw_value.to_s.match?(REQUIRES_UPPERCASE)
        raise Auth::Errors::WeakPassword, errors.join(". ") if errors.any?
        @raw = raw_value
      end
    end
  end
end
