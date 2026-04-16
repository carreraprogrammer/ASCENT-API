FactoryBot.define do
  factory :monthly_financial_plan do
    user
    account { user.default_account }
    month { 4 }
    year  { 2026 }
    status { "draft" }
    mode { "conservative" }
    base_budget_income { 6_400_000 }
    expected_variable_income { 2_900_000 }
    recurring_obligations_total { 2_500_000 }
    debt_minimums_total { 1_000_000 }
    protected_buffer_amount { 300_000 }
    discretionary_limit { 600_000 }
    overflow_rule { "debt" }
    overflow_rule_detail { { "debt" => 100 } }
    reward_pct { 5 }
    debt_strategy { "snowball" }
    assumptions { { "planning_income_used" => 6_400_000 } }
    confirmed_at { nil }
  end
end
