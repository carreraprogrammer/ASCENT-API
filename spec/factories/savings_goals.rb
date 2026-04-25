FactoryBot.define do
  factory :savings_goal do
    user
    account { user.default_account }
    name { "Fondo de emergencia" }
    target_amount { 5_000_000 }
    current_amount { 0 }
    target_date { Date.today >> 12 }
    monthly_contribution { 250_000 }
    status { "active" }
    priority { 0 }
  end
end
