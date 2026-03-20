module Auth
  module Repositories
    class UserRepository
      def find_by_email(email)
        record = ::User.find_by(email: email.to_s)
        record && map_to_entity(record)
      end
      def find_by_id(id)
        record = ::User.find_by(id: id)
        record && map_to_entity(record)
      end
      def create(email:, name:, encrypted_password:)
        record = ::User.create!(email: email.to_s, name: name, encrypted_password: encrypted_password)
        map_to_entity(record)
      end

      def find_by_google_uid(google_uid)
        record = ::User.find_by(google_uid: google_uid)
        record ? map_to_entity(record) : nil
      end

      def find_or_create_from_google(google_uid:, email:, name:, avatar_url:)
        record = ::User.find_by(google_uid: google_uid)

        unless record
          record = ::User.find_by(email: email)

          if record
            record.update!(
              google_uid: google_uid,
              avatar_url: avatar_url,
              auth_provider: "google"
            )
          else
            record = ::User.create!(
              email: email,
              name: name,
              google_uid: google_uid,
              avatar_url: avatar_url,
              auth_provider: "google",
              confirmed_at: Time.current
            )
          end
        end

        map_to_entity(record)
      end
      def save_refresh_token(user_id:, token_hash:, expires_at:)
        ::User.find(user_id).update!(refresh_token_hash: token_hash, refresh_token_expires_at: expires_at)
      end
      def invalidate_refresh_token(user_id:)
        ::User.find(user_id).update!(refresh_token_hash: nil, refresh_token_expires_at: nil)
      end
      private
      def map_to_entity(record)
        Auth::Entities::User.new(id: record.id, email: record.email, name: record.name,
          encrypted_password: record.encrypted_password, refresh_token_hash: record.refresh_token_hash,
          refresh_token_expires_at: record.refresh_token_expires_at, confirmed_at: record.confirmed_at,
          created_at: record.created_at, super_admin: record.super_admin,
          google_uid: record.google_uid, avatar_url: record.avatar_url, auth_provider: record.auth_provider)
      end
    end
  end
end
