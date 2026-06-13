require "rails_helper"

RSpec.describe "Gmail OAuth callback" do
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("APP_DEEP_LINK_BASE", anything)
      .and_return("daniel15k://auth/gmail")
  end

  it "serves an HTML page that deep-links back to the app on success" do
    allow(Auth::Interactors::GmailOauth).to receive(:exchange_code).and_return(true)

    get "/api/v1/auth/gmail/callback", params: { code: "abc", state: "signed-state" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("daniel15k://auth/gmail?status=connected")
    expect(response.body).to include("window.location.replace")
    expect(response.body).to include("Volver a la aplicación")
  end

  it "deep-links with an error status when the exchange fails" do
    allow(Auth::Interactors::GmailOauth).to receive(:exchange_code)
      .and_raise(StandardError, "boom")

    get "/api/v1/auth/gmail/callback", params: { code: "abc", state: "signed-state" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("status=error")
    expect(response.body).to include("reason=exchange_failed")
  end

  it "deep-links with an error when Google returns an error param" do
    get "/api/v1/auth/gmail/callback", params: { error: "access_denied" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("status=error")
    expect(response.body).to include("reason=access_denied")
  end
end
