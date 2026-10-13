class SetSuperAdminForOwner < ActiveRecord::Migration[8.0]
  # El dueño se configura por entorno (OWNER_EMAIL); sin la variable, la migración no hace nada.
  OWNER_EMAIL = ENV.fetch("OWNER_EMAIL", "").strip.downcase.freeze

  def up
    return if OWNER_EMAIL.empty?

    User.where(email: OWNER_EMAIL).update_all(super_admin: true)
  end

  def down
    return if OWNER_EMAIL.empty?

    User.where(email: OWNER_EMAIL).update_all(super_admin: false)
  end
end
