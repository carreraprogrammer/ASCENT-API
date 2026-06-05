require "rails_helper"

RSpec.describe "Gmail Pub/Sub webhook" do
  let(:account) { create(:account) }
  let(:secret) { "gmail-secret" }

  before do
    ActiveRecord::Encryption.config.primary_key = "0" * 32
    ActiveRecord::Encryption.config.deterministic_key = "1" * 32
    ActiveRecord::Encryption.config.key_derivation_salt = "2" * 32
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GMAIL_WEBHOOK_SECRET").and_return(secret)
    allow(Thread).to receive(:new).and_yield
  end

  def pubsub_payload(email_address:, history_id:)
    data = Base64.strict_encode64({ emailAddress: email_address, historyId: history_id }.to_json)
    { message: { data: data } }.to_json
  end

  def create_connection(history_id: "100")
    EmailConnection.create!(
      account: account,
      provider: "gmail",
      access_token: "access-token",
      refresh_token: "refresh-token",
      connected_at: Time.current,
      gmail_address: "daniel@example.com",
      gmail_history_id: history_id,
      gmail_watch_expires_at: 5.days.from_now
    )
  end

  it "calls the brain with the previous Gmail history id and advances after success" do
    conn = create_connection(history_id: "100")

    expect_any_instance_of(Api::V1::GmailWebhookController)
      .to receive(:call_brain)
      .with(account_id: account.id, history_id: "100")
      .and_return(true)

    post "/api/v1/webhooks/gmail?token=#{secret}",
      params: pubsub_payload(email_address: "daniel@example.com", history_id: "125"),
      headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(conn.reload.gmail_history_id).to eq("125")
  end

  it "keeps the previous Gmail history id when the brain call fails" do
    conn = create_connection(history_id: "100")

    expect_any_instance_of(Api::V1::GmailWebhookController)
      .to receive(:call_brain)
      .with(account_id: account.id, history_id: "100")
      .and_return(false)

    post "/api/v1/webhooks/gmail?token=#{secret}",
      params: pubsub_payload(email_address: "daniel@example.com", history_id: "125"),
      headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(conn.reload.gmail_history_id).to eq("100")
  end

  it "ignores already processed Gmail history ids" do
    conn = create_connection(history_id: "125")

    expect_any_instance_of(Api::V1::GmailWebhookController)
      .not_to receive(:call_brain)

    post "/api/v1/webhooks/gmail?token=#{secret}",
      params: pubsub_payload(email_address: "daniel@example.com", history_id: "125"),
      headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(conn.reload.gmail_history_id).to eq("125")
  end
end
