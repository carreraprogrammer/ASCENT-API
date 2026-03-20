module Authorization
  module Repositories
    class UserRoleRepository
      def assign(user_id:, role_id:, expires_at: nil)
        ::UserRole.find_or_create_by!(user_id: user_id, role_id: role_id) { |ur| ur.expires_at = expires_at }
      end
      def revoke(user_id:, role_id:)
        ::UserRole.find_by(user_id: user_id, role_id: role_id)&.destroy!
      end
      def permissions_for_user(user_id)
        ::Permission.joins(roles: :user_roles)
          .where(user_roles: { user_id: user_id })
          .where("user_roles.expires_at IS NULL OR user_roles.expires_at > ?", Time.current)
          .distinct.map { |p| "#{p.resource}:#{p.action}" }
      end
      def roles_for_user(user_id)
        ::Role.joins(:user_roles).where(user_roles: { user_id: user_id }).active
          .where("user_roles.expires_at IS NULL OR user_roles.expires_at > ?", Time.current)
      end
    end
  end
end
