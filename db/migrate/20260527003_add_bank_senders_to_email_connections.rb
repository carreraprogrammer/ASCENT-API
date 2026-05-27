class AddBankSendersToEmailConnections < ActiveRecord::Migration[8.0]
  def change
    # Array JSON de remitentes bancarios configurados por el usuario.
    # null / [] = sin configurar → el agente usa búsqueda por keywords financieros.
    # ["email@banco.com", ...] = el agente busca solo esos remitentes (más preciso).
    add_column :email_connections, :bank_senders, :text, null: true
  end
end
