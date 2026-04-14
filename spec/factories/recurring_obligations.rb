FactoryBot.define do
  factory :recurring_obligation do
    user
    category
    name    { "Arriendo" }
    amount  { 2_500_000 }
    due_day { 5 }
    active  { true }

    trait :debt_payment do
      name    { "CrediExpress" }
      amount  { 866_000 }
      due_day { 10 }
    end

    trait :inactive do
      active { false }
    end
  end
end
