require "rails_helper"

# ASC-4 fase 6: modo demo.
RSpec.describe "Demo mode" do
  let(:service_token) { "test-service-token" }
  let!(:service_account) do
    ServiceAccount.create!(name: "Brain", slug: "daniel15k-brain").tap { |sa| sa.store_raw_token!(service_token) }
  end
  let!(:agent_type) { AgentType.create!(name: "Finance Coach", slug: "finance_coach") }
  let(:service_headers) { { "Authorization" => "Bearer #{service_token}" } }

  let(:demo) { Demo::Interactors::ResetDemoAccount.new.call }
  let(:demo_account_id) { demo[:account_id] }

  let(:real_user) { create(:user) }
  let(:real_account) { Account.where(owner_user_id: real_user.id).order(:id).first }

  def json = JSON.parse(response.body)

  def demo_headers
    post "/api/v1/demo/session"
    { "Authorization" => "Bearer #{json.dig('meta', 'access_token')}" }
  end

  describe "POST /api/v1/demo/session" do
    it "returns the login shape with user.demo = true, a demo claim and no refresh token" do
      demo

      post "/api/v1/demo/session"

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "attributes", "demo")).to be(true)
      expect(json.dig("data", "attributes", "default_account_id")).to eq(demo_account_id)
      expect(json.dig("meta", "refresh_token")).to be_nil
      expect(json.dig("meta", "expires_in")).to eq(Demo::Config.session_ttl)

      payload = JwtService.decode(json.dig("meta", "access_token"))
      expect(payload[:demo]).to be(true)
      expect(payload[:super_admin]).to be(false)
      expect(payload[:exp]).to be <= Time.current.to_i + Demo::Config.session_ttl
    end

    it "answers 404 when the demo account has not been seeded" do
      post "/api/v1/demo/session"
      expect(response).to have_http_status(:not_found)
    end

    it "is rate limited by IP" do
      throttle = Rack::Attack.throttles["demo/session/ip"]
      expect(throttle).to be_present
      expect(throttle.limit).to be <= 10
    end
  end

  describe "isolation" do
    before do
      demo
      create(:debt, user: real_user, account: real_account, name: "Deuda real")
    end

    it "reads only the demo account" do
      get "/api/v1/debts", headers: demo_headers

      expect(response).to have_http_status(:ok)
      names = json["data"].map { |d| d["name"] || d.dig("attributes", "name") }
      expect(names).to include("Crédito moto")
      expect(names).not_to include("Deuda real")
    end

    it "cannot read another account's data with X-Account-Id" do
      get "/api/v1/debts", headers: demo_headers.merge("X-Account-Id" => real_account.id.to_s)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Deuda real")
    end
  end

  describe "read-only" do
    before { demo }

    it "rejects every write with 403 demo_read_only" do
      headers = demo_headers
      debt_id = Debt.where(account_id: demo_account_id).first.id

      post "/api/v1/transactions", params: { concept: "x", amount: 1000, date: "2026-11-01" }, headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "demo_read_only")

      patch "/api/v1/debts/#{debt_id}", params: { name: "otra" }, headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "demo_read_only")

      delete "/api/v1/debts/#{debt_id}", headers: headers
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/auth/gmail", headers: headers
      expect(response).to have_http_status(:forbidden)

      expect(Debt.find(debt_id).name).not_to eq("otra")
    end

    it "still allows logout" do
      delete "/api/v1/auth/logout", headers: demo_headers
      expect(response).to have_http_status(:no_content)
    end

    it "blocks writes for the demo user even with a token that lacks the claim" do
      user = User.find_by!(email: Demo::Config.email)
      post "/api/v1/transactions", params: { concept: "x", amount: 1000 }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "demo_read_only")
    end

    it "lets the agent read the demo account but not write to it" do
      headers = service_headers.merge("X-Account-Id" => demo_account_id.to_s, "X-Agent-Type" => "finance_coach")

      get "/api/v1/debts", headers: headers
      expect(response).to have_http_status(:ok)

      post "/api/v1/transactions", params: { concept: "x", amount: 1000 }, headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "demo_read_only")
    end

    it "does not affect normal users" do
      post "/api/v1/debts", params: { name: "Nueva", current_balance: 1000, monthly_payment: 100 },
                            headers: auth_headers_for(real_user)
      expect(response.status).not_to eq(403)
    end
  end

  describe "POST /api/v1/demo/switch" do
    before { demo }

    it "returns the demo session for the superadmin" do
      admin = create(:user, super_admin: true)

      post "/api/v1/demo/switch", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "attributes", "demo")).to be(true)
      payload = JwtService.decode(json.dig("meta", "access_token"))
      expect(payload).to include(demo: true, user_id: User.find_by!(email: Demo::Config.email).id,
                                 impersonated_by: admin.id)
    end

    it "is forbidden for anyone else" do
      post "/api/v1/demo/switch", headers: auth_headers_for(real_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "is forbidden for a demo session" do
      post "/api/v1/demo/switch", headers: demo_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/demo/switch"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "agents service" do
    before do
      demo
      real_account
    end

    it "excludes the demo account from active accounts" do
      get "/api/v1/agent/accounts/active", headers: service_headers

      ids = json["data"].map { |a| a["id"] }
      expect(ids).to include(real_account.id)
      expect(ids).not_to include(demo_account_id)
    end

    it "returns the demo account id with the service token only" do
      get "/api/v1/agent/accounts/demo", headers: service_headers
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "id")).to eq(demo_account_id)

      get "/api/v1/agent/accounts/demo", headers: auth_headers_for(real_user)
      expect(response).to have_http_status(:unauthorized)
    end

    it "resets the demo account with the service token" do
      Debt.where(account_id: demo_account_id).update_all(current_balance: 1)

      post "/api/v1/agent/demo/reset", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "account_id")).to eq(demo_account_id)
      expect(Debt.where(account_id: demo_account_id).pluck(:current_balance)).not_to include(1)

      post "/api/v1/agent/demo/reset"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
