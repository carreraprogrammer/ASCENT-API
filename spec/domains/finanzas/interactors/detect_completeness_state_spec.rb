require "rails_helper"

RSpec.describe Finanzas::Interactors::DetectCompletenessState do
  subject(:interactor) { described_class.new }

  let(:user)       { create(:user, :confirmed) }
  let(:account_id) { user.default_account.id }
  let(:month)      { 5 }
  let(:year)       { 2026 }

  def call
    interactor.call(account_id: account_id, month: month, year: year)
  end

  describe "monthly_plan dimension" do
    context "when no plan exists" do
      it "returns status missing" do
        result = call
        expect(result[:dimensions]["monthly_plan"][:status]).to eq("missing")
      end
    end

    context "when a confirmed plan exists" do
      before do
        create(:monthly_financial_plan,
          user: user, month: month, year: year,
          status: "confirmed", confirmed_at: Time.current)
      end

      it "returns status sufficient" do
        result = call
        expect(result[:dimensions]["monthly_plan"][:status]).to eq("sufficient")
      end
    end

    context "when a draft plan exists WITHOUT inherited_from in assumptions" do
      before do
        create(:monthly_financial_plan,
          user: user, month: month, year: year,
          status: "draft", confirmed_at: nil,
          assumptions: { "generated_from" => "income_sources" })
      end

      it "returns status partial" do
        result = call
        expect(result[:dimensions]["monthly_plan"][:status]).to eq("partial")
      end
    end

    context "when a draft plan exists WITH inherited_from (rolling plan)" do
      before do
        create(:monthly_financial_plan,
          user: user, month: month, year: year,
          status: "draft", confirmed_at: nil,
          assumptions: {
            "inherited_from" => { "month" => 4, "year" => 2026 },
            "rolling_changes" => ["base_budget_income sin cambios"]
          })
      end

      it "returns status pending_confirmation" do
        result = call
        expect(result[:dimensions]["monthly_plan"][:status]).to eq("pending_confirmation")
      end

      it "includes rolling_changes in the observed data" do
        result = call
        observed = result[:dimensions]["monthly_plan"][:observed]
        expect(observed[:rolling_changes]).to be_an(Array)
      end

      it "includes inherited_from in the observed data" do
        result = call
        observed = result[:dimensions]["monthly_plan"][:observed]
        expect(observed[:inherited_from]).to be_present
      end
    end
  end

  describe "result structure" do
    it "always includes the monthly_plan dimension" do
      result = call
      expect(result[:dimensions]).to have_key("monthly_plan")
    end

    it "includes pending in the partial array when plan is draft without rolling" do
      create(:monthly_financial_plan,
        user: user, month: month, year: year,
        status: "draft", confirmed_at: nil,
        assumptions: {})
      result = call
      expect(result[:partial]).to include("monthly_plan")
    end

    it "does NOT include monthly_plan in missing, partial, or stale when pending_confirmation" do
      create(:monthly_financial_plan,
        user: user, month: month, year: year,
        status: "draft", confirmed_at: nil,
        assumptions: { "inherited_from" => { "month" => 4, "year" => 2026 } })
      result = call
      expect(result[:missing]).not_to include("monthly_plan")
      expect(result[:partial]).not_to include("monthly_plan")
      expect(result[:stale]).not_to include("monthly_plan")
    end
  end
end
