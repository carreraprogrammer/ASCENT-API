class AddReconnectRequiredToEmailConnections < ActiveRecord::Migration[8.0]
  def change
    # Se setea cuando el refresh token muere (el usuario debe reconectar Gmail).
    # nil = conexión sana. Se limpia al reconectar.
    add_column :email_connections, :reconnect_required_at, :datetime
  end
end
