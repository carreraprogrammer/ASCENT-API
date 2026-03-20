module Authorization
  module Interactors
    class RevokePermissionFromRole
      def initialize(role_repo: Repositories::RoleRepository.new, permission_repo: Repositories::PermissionRepository.new)
        @role_repo = role_repo
        @permission_repo = permission_repo
      end

      def call(role_id:, permission_slug:)
        permission = @permission_repo.find_by_slug(permission_slug)
        @role_repo.revoke_permission(role_id: role_id, permission_id: permission.id)
      end
    end
  end
end
