FactoryBot.define do
  factory :sinking_fund do
    user
    account { user.default_account }
    name { "SOAT moto" }
    monthly_contribution { 140_000 }
    target_amount { 420_000 }
    target_date { Date.current + 3.months }
    current_balance { 0 }
    budget_category { "necessary" }
    active { true }
  end
end
