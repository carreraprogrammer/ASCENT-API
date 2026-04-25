require "rails_helper"

RSpec.describe Finanzas::Interactors::ProposeBudget do
  subject(:interactor) { described_class.new }

  let(:user)    { create(:user) }
  let(:account) { user.default_account }
  let(:month) { 5 }
  let(:year)  { 2026 }

  # Helper: stub BuildBudgetContext to return controlled data
  def stub_ctx(spending_history: {}, gaps: {})
    ctx = {
      income: {
        fixed_total: 6_400_000,
        variable_projection: 1_450_000,
        fixed_sources: [],
        variable_sources: []
      },
      obligations: { total: 2_500_000, by_category: {} },
      debt_minimums: { total: 1_000_000 },
      sinking_funds: [],
      planned_expenses: [],
      budget_categories: [],
      spending_history: spending_history,
      gaps: { missing_income: false, missing_obligations: false,
              obligations_seem_low: false }.merge(gaps),
      existing_plan: nil
    }
    allow_any_instance_of(Finanzas::Interactors::BuildBudgetContext)
      .to receive(:call).and_return(ctx)
  end

  # Helper: build a closed plan entity (hash)
  def closed_plan(month:, year:, base_budget_income:, income_actual:,
                  execution_snapshot: {})
    {
      id: rand(1000),
      account_id: account.id,
      month: month,
      year: year,
      status: "confirmed",
      confirmed_at: Time.current,
      closed_at: Time.current,
      base_budget_income: base_budget_income,
      income_actual: income_actual,
      execution_snapshot: execution_snapshot
    }
  end

  describe "historical_patterns" do
    context "when no closed plans exist" do
      before { stub_ctx }

      it "returns an empty historical_patterns array" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        expect(result[:historical_patterns]).to eq([])
      end
    end

    context "when a category consistently overshoots" do
      before do
        stub_ctx(spending_history: { "discretionary" => { average_monthly: 520_000, months_with_data: 3 } })

        plans = [
          closed_plan(month: 4, year: 2026, base_budget_income: 6_400_000, income_actual: 6_400_000,
            execution_snapshot: { "categories" => [
              { "code" => "discretionary", "budgeted" => 400_000, "actual" => 480_000, "variance_pct" => 20 }
            ]}),
          closed_plan(month: 3, year: 2026, base_budget_income: 6_400_000, income_actual: 6_400_000,
            execution_snapshot: { "categories" => [
              { "code" => "discretionary", "budgeted" => 400_000, "actual" => 500_000, "variance_pct" => 25 }
            ]}),
          closed_plan(month: 2, year: 2026, base_budget_income: 6_400_000, income_actual: 6_400_000,
            execution_snapshot: { "categories" => [
              { "code" => "discretionary", "budgeted" => 400_000, "actual" => 460_000, "variance_pct" => 15 }
            ]})
        ]

        allow_any_instance_of(Finanzas::Repositories::MonthlyFinancialPlanRepository)
          .to receive(:last_closed).with(account_id: account.id, limit: 3).and_return(plans)
      end

      it "detects the consistently_over pattern" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        pattern = result[:historical_patterns].find { |p| p[:pattern] == "consistently_over" }
        expect(pattern).to be_present
        expect(pattern[:category_code]).to eq("discretionary")
      end

      it "reports the average variance percentage" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        pattern = result[:historical_patterns].find { |p| p[:pattern] == "consistently_over" }
        expect(pattern[:avg_variance_pct]).to eq(20)
      end

      it "includes a human-readable suggestion" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        pattern = result[:historical_patterns].find { |p| p[:pattern] == "consistently_over" }
        expect(pattern[:suggestion]).to be_present
      end
    end

    context "when a category overshoots in only 1 of 3 months" do
      before do
        stub_ctx

        plans = [
          closed_plan(month: 4, year: 2026, base_budget_income: 6_400_000, income_actual: 6_400_000,
            execution_snapshot: { "categories" => [
              { "code" => "dining_out", "budgeted" => 200_000, "actual" => 240_000, "variance_pct" => 20 }
            ]}),
          closed_plan(month: 3, year: 2026, base_budget_income: 6_400_000, income_actual: 6_400_000,
            execution_snapshot: { "categories" => [
              { "code" => "dining_out", "budgeted" => 200_000, "actual" => 190_000, "variance_pct" => -5 }
            ]}),
          closed_plan(month: 2, year: 2026, base_budget_income: 6_400_000, income_actual: 6_400_000,
            execution_snapshot: { "categories" => [
              { "code" => "dining_out", "budgeted" => 200_000, "actual" => 180_000, "variance_pct" => -10 }
            ]})
        ]

        allow_any_instance_of(Finanzas::Repositories::MonthlyFinancialPlanRepository)
          .to receive(:last_closed).with(account_id: account.id, limit: 3).and_return(plans)
      end

      it "does not flag consistently_over for that category" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        over_patterns = result[:historical_patterns].select { |p| p[:pattern] == "consistently_over" }
        expect(over_patterns).to be_empty
      end
    end

    context "when income was consistently overestimated" do
      before do
        stub_ctx

        plans = [
          closed_plan(month: 4, year: 2026, base_budget_income: 6_400_000, income_actual: 5_800_000),
          closed_plan(month: 3, year: 2026, base_budget_income: 6_400_000, income_actual: 5_900_000),
          closed_plan(month: 2, year: 2026, base_budget_income: 6_400_000, income_actual: 6_500_000)
        ]

        allow_any_instance_of(Finanzas::Repositories::MonthlyFinancialPlanRepository)
          .to receive(:last_closed).with(account_id: account.id, limit: 3).and_return(plans)
      end

      it "detects the income_overestimated pattern (2 of 3 months short)" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        pattern = result[:historical_patterns].find { |p| p[:pattern] == "income_overestimated" }
        expect(pattern).to be_present
      end

      it "reports the average shortfall" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        pattern = result[:historical_patterns].find { |p| p[:pattern] == "income_overestimated" }
        expect(pattern[:avg_shortfall]).to be > 0
      end
    end

    context "when income was accurate in all months" do
      before do
        stub_ctx

        plans = [
          closed_plan(month: 4, year: 2026, base_budget_income: 6_400_000, income_actual: 6_450_000),
          closed_plan(month: 3, year: 2026, base_budget_income: 6_400_000, income_actual: 6_380_000)
        ]

        allow_any_instance_of(Finanzas::Repositories::MonthlyFinancialPlanRepository)
          .to receive(:last_closed).with(account_id: account.id, limit: 3).and_return(plans)
      end

      it "does not flag income_overestimated" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        pattern = result[:historical_patterns].find { |p| p[:pattern] == "income_overestimated" }
        expect(pattern).to be_nil
      end
    end

    context "when multiple patterns exist simultaneously" do
      before do
        stub_ctx(spending_history: { "discretionary" => { average_monthly: 520_000, months_with_data: 3 } })

        plans = [
          closed_plan(month: 4, year: 2026, base_budget_income: 6_400_000, income_actual: 5_800_000,
            execution_snapshot: { "categories" => [
              { "code" => "discretionary", "budgeted" => 400_000, "actual" => 490_000, "variance_pct" => 22 }
            ]}),
          closed_plan(month: 3, year: 2026, base_budget_income: 6_400_000, income_actual: 5_700_000,
            execution_snapshot: { "categories" => [
              { "code" => "discretionary", "budgeted" => 400_000, "actual" => 480_000, "variance_pct" => 20 }
            ]}),
          closed_plan(month: 2, year: 2026, base_budget_income: 6_400_000, income_actual: 6_500_000,
            execution_snapshot: { "categories" => [
              { "code" => "discretionary", "budgeted" => 400_000, "actual" => 420_000, "variance_pct" => 5 }
            ]})
        ]

        allow_any_instance_of(Finanzas::Repositories::MonthlyFinancialPlanRepository)
          .to receive(:last_closed).with(account_id: account.id, limit: 3).and_return(plans)
      end

      it "returns both patterns" do
        result = interactor.call(account_id: account.id, month: month, year: year)
        codes = result[:historical_patterns].map { |p| p[:pattern] }
        expect(codes).to include("consistently_over", "income_overestimated")
      end
    end
  end

  describe "result structure" do
    before do
      stub_ctx
      allow_any_instance_of(Finanzas::Repositories::MonthlyFinancialPlanRepository)
        .to receive(:last_closed).and_return([])
    end

    it "always includes historical_patterns in the result" do
      result = interactor.call(account_id: account.id, month: month, year: year)
      expect(result).to have_key(:historical_patterns)
    end

    it "preserves all existing keys in the result" do
      result = interactor.call(account_id: account.id, month: month, year: year)
      %i[income committed categories free_margin warnings month year].each do |key|
        expect(result).to have_key(key)
      end
    end
  end
end
