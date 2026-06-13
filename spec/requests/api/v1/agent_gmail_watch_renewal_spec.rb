require "rails_helper"

RSpec.describe "Agent Gmail watch renewal" do
  let(:account) { create(:account) }
  let(:service_token) { "test-service-token" }

  before do
    ActiveRecord::Encryption.config.primary_key = "0" * 32
    ActiveRecord::Encryption.config.deterministic_key = "1" * 32
    ActiveRecord::Encryption.config.key_derivation_salt = "2" * 32

    service_account = ServiceAccount.create!(name: "Finance Agent", slug: "finance-agent")
    service_account.store_raw_token!(service_token)
  end

  def create_connection(expires_at:, on_account: account)
    EmailConnection.create!(
      account: on_account,
      provider: "gmail",
      access_token: "access-token",
      refresh_token: "refresh-token",
      connected_at: Time.current,
      gmail_address: "daniel+#{on_account.id}@example.com",
      gmail_history_id: "100",
      gmail_watch_expires_at: expires_at
    )
  end

  it "rejects requests without a valid service token" do
    post "/api/v1/agent/gmail/renew_watches"
    expect(response).to have_http_status(:unauthorized)
  end

  it "renews watches expiring within two days and reports counts" do
    create_connection(expires_at: 1.day.from_now)
    create_connection(expires_at: 5.days.from_now, on_account: create(:account))

    expect(Auth::Interactors::GmailWatchRegistrar)
      .to receive(:call).with(account_id: account.id).once

    post "/api/v1/agent/gmail/renew_watches",
      headers: { "Authorization" => "Bearer #{service_token}" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)["data"]
    expect(body).to include("candidates" => 1, "renewed" => 1, "failed" => 0)
  end

  it "counts failures without aborting the batch" do
    create_connection(expires_at: 1.day.from_now)

    allow(Auth::Interactors::GmailWatchRegistrar)
      .to receive(:call).and_raise(StandardError, "gmail down")

    post "/api/v1/agent/gmail/renew_watches",
      headers: { "Authorization" => "Bearer #{service_token}" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)["data"]
    expect(body).to include("candidates" => 1, "renewed" => 0, "failed" => 1)
  end
end
