FactoryBot.define do
  factory :debt do
    user
    account { user.default_account }
    name { "CrediExpress" }
    debt_type { "personal_loan" }
    original_amount { 5_000_000 }
    current_balance { 4_000_000 }
    monthly_payment { 800_000 }
    interest_rate { 3.2 }
    status { "active" }
  end
end
