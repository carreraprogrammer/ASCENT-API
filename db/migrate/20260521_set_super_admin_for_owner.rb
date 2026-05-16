class SetSuperAdminForOwner < ActiveRecord::Migration[8.0]
  OWNER_EMAIL = "carreraprogrammer@gmail.com".freeze

  def up
    User.where(email: OWNER_EMAIL).update_all(super_admin: true)
  end

  def down
    User.where(email: OWNER_EMAIL).update_all(super_admin: false)
  end
end
