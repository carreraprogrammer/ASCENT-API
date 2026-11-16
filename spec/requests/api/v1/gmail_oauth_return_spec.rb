require "rails_helper"

# ASC-4 fase 2: el regreso después de conectar Gmail. La web termina con un 302 a la página de la UI;
# iOS conserva el deep link (state sin plataforma, igual que antes).
RSpec.describe "Gmail OAuth return (web and iOS)" do
  let(:frontend) { "https://ascent.thecyborgway.dev" }
  let(:account) { create(:account) }
  let(:verifier) { Rails.application.message_verifier(:gmail_oauth) }
  let(:web_state) { verifier.generate("#{account.id}:web", expires_in: 10.minutes) }
  let(:ios_state) { verifier.generate(account.id.to_s, expires_in: 10.minutes) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("FRONTEND_URL", anything).and_return(frontend)
    allow(ENV).to receive(:fetch).with("APP_DEEP_LINK_BASE", anything).and_return("daniel15k://auth/gmail")
    allow(ENV).to receive(:fetch).with("GOOGLE_CLIENT_ID").and_return("client-id")
  end

  describe "GET /api/v1/auth/gmail/callback" do
    it "redirects the web to FRONTEND_URL/auth/gmail/callback?status=connected" do
      expect(Auth::Interactors::GmailOauth).to receive(:exchange_code).with(code: "abc", state: web_state)

      get "/api/v1/auth/gmail/callback", params: { code: "abc", state: web_state }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("#{frontend}/auth/gmail/callback?status=connected")
    end

    it "redirects the web with status=error when Google returns an error" do
      get "/api/v1/auth/gmail/callback", params: { error: "access_denied", state: web_state }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("#{frontend}/auth/gmail/callback?status=error&reason=access_denied")
    end

    it "redirects the web with status=error when the exchange fails" do
      allow(Auth::Interactors::GmailOauth).to receive(:exchange_code).and_raise(StandardError, "boom")

      get "/api/v1/auth/gmail/callback", params: { code: "abc", state: web_state }

      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("#{frontend}/auth/gmail/callback?status=error")
    end

    it "keeps the iOS deep link page for a state without platform" do
      allow(Auth::Interactors::GmailOauth).to receive(:exchange_code).and_return(account)

      get "/api/v1/auth/gmail/callback", params: { code: "abc", state: ios_state }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("daniel15k://auth/gmail?status=connected")
      expect(response.body).to include("Volver a la aplicación")
    end
  end

  describe "POST /api/v1/auth/gmail" do
    let(:user) { create(:user) }
    let(:user_account_id) { Account.where(owner_user_id: user.id).order(:id).pick(:id) }

    def state_payload
      state = Rack::Utils.parse_query(URI(JSON.parse(response.body).dig("data", "authorization_url")).query)["state"]
      verifier.verify(state)
    end

    it "signs the web platform in the state when the request comes from the web origin" do
      post "/api/v1/auth/gmail", headers: auth_headers_for(user).merge("Origin" => frontend)

      expect(response).to have_http_status(:ok)
      expect(state_payload).to eq("#{user_account_id}:web")
    end

    it "keeps the iOS state exactly as before (account id only)" do
      post "/api/v1/auth/gmail", headers: auth_headers_for(user).merge("Origin" => "capacitor://localhost")

      expect(state_payload).to eq(user_account_id.to_s)
    end

    it "honours an explicit platform param" do
      post "/api/v1/auth/gmail", params: { platform: "ios" }, headers: auth_headers_for(user).merge("Origin" => frontend)

      expect(state_payload).to eq(user_account_id.to_s)
    end
  end

  describe "Auth::Interactors::GmailOauth.decode_state" do
    it "reads legacy and web states" do
      expect(Auth::Interactors::GmailOauth.decode_state(ios_state)).to eq(account_id: account.id.to_s, platform: "native")
      expect(Auth::Interactors::GmailOauth.decode_state(web_state)).to eq(account_id: account.id.to_s, platform: "web")
    end

    it "falls back to the app when the state cannot be read" do
      expect(Auth::Interactors::GmailOauth.return_platform("tampered")).to eq("native")
    end
  end
end
