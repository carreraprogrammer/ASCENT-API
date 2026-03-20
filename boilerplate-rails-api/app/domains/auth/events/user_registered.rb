module Auth
  module Events
    class UserRegistered
      attr_reader :user_id, :email, :occurred_at
      def initialize(user_id:, email:)
        @user_id = user_id
        @email = email
        @occurred_at = Time.current
      end
    end
  end
end
