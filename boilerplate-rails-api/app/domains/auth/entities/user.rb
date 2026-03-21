module Auth
  module Entities
    class User
      attr_reader :id, :email, :name, :encrypted_password,
                  :refresh_token_hash, :refresh_token_expires_at,
                  :confirmed_at, :created_at, :super_admin,
                  :google_uid, :avatar_url, :auth_provider

      def initialize(attrs = {})
        @id = attrs[:id]
        @email = attrs[:email]
        @name = attrs[:name]
        @encrypted_password = attrs[:encrypted_password]
        @refresh_token_hash = attrs[:refresh_token_hash]
        @refresh_token_expires_at = attrs[:refresh_token_expires_at]
        @confirmed_at = attrs[:confirmed_at]
        @created_at = attrs[:created_at]
        @super_admin = attrs[:super_admin] || false
        @google_uid = attrs[:google_uid]
        @avatar_url = attrs[:avatar_url]
        @auth_provider = attrs[:auth_provider]
      end

      def confirmed? = !confirmed_at.nil?
      def super_admin? = @super_admin == true

      def oauth_user?
        auth_provider.present?
      end

      def refresh_token_valid?(raw_token)
        return false if refresh_token_hash.nil?
        return false if refresh_token_expires_at.nil? || refresh_token_expires_at < Time.current

        BCrypt::Password.new(refresh_token_hash) == raw_token
      end
    end
  end
end
