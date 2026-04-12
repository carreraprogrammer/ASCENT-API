FactoryBot.define do
  factory :transaction do
    user
    date { "11/04" }
    concept { Faker::Commerce.product_name }
    product { "tc7248" }
    amount { 50_000 }
    transaction_type { "expense" }
    source { "manual" }
    status { "confirmed" }
    year { 2026 }
    month { 4 }
    metadata { {} }

    trait :pending do
      status { "pending" }
    end

    trait :income do
      transaction_type { "income" }
      amount { 5_000_000 }
    end

    trait :projected do
      status { "projected" }
    end
  end
end
