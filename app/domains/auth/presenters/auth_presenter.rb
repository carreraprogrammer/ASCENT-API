module Auth
  module Presenters
    class AuthPresenter
      def self.user_with_tokens(user:, access_token:, refresh_token:)
        { data: user_resource(user), meta: { access_token: access_token, refresh_token: refresh_token } }
      end
      def self.user(user)
        { data: user_resource(user) }
      end
      def self.tokens(access_token:, refresh_token:)
        { meta: { access_token: access_token, refresh_token: refresh_token } }
      end

      def self.user_resource(user)
        account = Account.active.where(owner_user_id: user.id).order(:id).first
        {
          id: user.id.to_s,
          type: "users",
          attributes: {
            email: user.email,
            name: user.name,
            city: user.city,
            confirmed: user.confirmed?,
            created_at: user.created_at,
            avatar_url: user.avatar_url,
            auth_provider: user.auth_provider,
            default_account_id: account&.id,
            default_account_slug: account&.slug
          }
        }
      end
    end
  end
end
