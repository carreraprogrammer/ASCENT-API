module Authorization
  module Interactors
    class CreateRole
      def initialize(role_repo: Repositories::RoleRepository.new)
        @role_repo = role_repo
      end

      def call(name:, slug:, description: nil)
        @role_repo.create(name: name, slug: slug, description: description)
      end
    end
  end
end
