module Auth
  module Presenters
    class AuthPresenter
      def self.user_with_tokens(user:, access_token:, refresh_token:)
        { data: { id: user.id.to_s, type: "users", attributes: { email: user.email, name: user.name, confirmed: user.confirmed?, created_at: user.created_at } }, meta: { access_token: access_token, refresh_token: refresh_token } }
      end
      def self.user(user)
        { data: { id: user.id.to_s, type: "users", attributes: { email: user.email, name: user.name, confirmed: user.confirmed?, created_at: user.created_at } } }
      end
      def self.tokens(access_token:, refresh_token:)
        { meta: { access_token: access_token, refresh_token: refresh_token } }
      end
    end
  end
end
