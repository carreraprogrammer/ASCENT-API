module Authorization
  module Presenters
    class UserPresenter
      def self.single(user)
        { data: serialize(user) }
      end

      def self.collection(users)
        { data: users.map { |user| serialize(user) }, meta: { total: users.size } }
      end

      def self.serialize(user)
        { id: user.id.to_s, type: "users", attributes: { email: user.email, name: user.name, super_admin: user.super_admin } }
      end
      private_class_method :serialize
    end
  end
end
