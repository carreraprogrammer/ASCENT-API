FactoryBot.define do
  factory :financial_context do
    user
    phase      { "debt_payoff" }
    strategy   { "snowball" }
    reward_pct { 5 }
    notes      { nil }
  end
end
