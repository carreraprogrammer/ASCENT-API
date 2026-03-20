module Auth
  module ValueObjects
    class Email
      VALID_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
      attr_reader :value
      def initialize(raw_value)
        normalized = raw_value.to_s.strip.downcase
        raise Auth::Errors::InvalidEmail, "Invalid email format: #{raw_value}" unless normalized.match?(VALID_FORMAT)
        raise Auth::Errors::InvalidEmail, "Email exceeds 255 characters" if normalized.length > 255
        @value = normalized
      end
      def to_s = @value
      def ==(other) = other.is_a?(Email) && value == other.value
    end
  end
end
