module Authorization
  UserContext = Struct.new(:user, :permissions, keyword_init: true) do
    def super_admin?
      user.super_admin?
    end

    def id
      user.id
    end
  end
end
