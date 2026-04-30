require "rails_helper"

RSpec.describe "Agent UI Events API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/agent_events/pending" do
    it "expires stale pending events before returning pending events" do
      old_event = AgentUiEvent.create!(
        account: user.default_account,
        event_type: "open_wizard",
        payload: { wizard: "budget_planning" },
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )
      recent_event = AgentUiEvent.create!(
        account: user.default_account,
        event_type: "show_card",
        payload: { title: "Actual", body: "Listo", tone: "info" }
      )

      get "/api/v1/agent_events/pending", headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.map { |event| event["id"] }).to eq([recent_event.id])
      expect(old_event.reload.consumed_at).to be_present
    end
  end
end
