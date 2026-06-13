require "rails_helper"

RSpec.describe Auth::Interactors::GmailOauth do
  let(:account) { create(:account) }

  before do
    ActiveRecord::Encryption.config.primary_key = "0" * 32
    ActiveRecord::Encryption.config.deterministic_key = "1" * 32
    ActiveRecord::Encryption.config.key_derivation_salt = "2" * 32
  end

  def create_connection(reconnect_required_at: nil)
    EmailConnection.create!(
      account: account,
      provider: "gmail",
      access_token: "access-token",
      refresh_token: "refresh-token",
      connected_at: Time.current,
      expires_at: 1.hour.ago, # expirado → fuerza refresh
      gmail_address: "daniel@example.com",
      reconnect_required_at: reconnect_required_at
    )
  end

  describe ".fresh_connection cuando el refresh token muere" do
    before do
      allow(described_class).to receive(:fetch_tokens)
        .and_raise(StandardError, "invalid_grant")
    end

    it "marca la conexión como needs_reconnect y re-lanza" do
      conn = create_connection

      expect { described_class.fresh_connection(account_id: account.id) }
        .to raise_error(StandardError, "invalid_grant")

      expect(conn.reload.needs_reconnect?).to be(true)
    end

    it "emite un agent_event show_card de reconexión" do
      create_connection

      expect {
        described_class.fresh_connection(account_id: account.id) rescue nil
      }.to change { AgentUiEvent.where(account_id: account.id).count }.by(1)

      event = AgentUiEvent.last
      expect(event.event_type).to eq("show_card")
      expect(event.payload["action"]).to eq("reconnect_gmail")
    end

    it "no duplica el aviso si ya estaba marcada" do
      create_connection(reconnect_required_at: 2.days.ago)

      expect {
        described_class.fresh_connection(account_id: account.id) rescue nil
      }.not_to change { AgentUiEvent.where(account_id: account.id).count }
    end
  end

  describe "reconexión exitosa" do
    it "limpia el flag al intercambiar un código nuevo" do
      conn = create_connection(reconnect_required_at: 1.day.ago)

      allow(Rails.application.message_verifier(:gmail_oauth))
        .to receive(:verify).and_return(account.id.to_s)
      allow(described_class).to receive(:fetch_tokens)
        .and_return("access_token" => "new", "refresh_token" => "new-refresh", "expires_in" => 3600)
      allow(Thread).to receive(:new).and_yield
      allow(Auth::Interactors::GmailWatchRegistrar).to receive(:call)

      described_class.exchange_code(code: "abc", state: "signed")

      expect(conn.reload.needs_reconnect?).to be(false)
    end
  end
end
