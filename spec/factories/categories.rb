FactoryBot.define do
  factory :category do
    user { nil }
    name { Faker::Commerce.department(max: 1, fixed_amount: true) }
    sequence(:code) { |n| "category_#{n}" }
    category_type { "discretionary" }
    color { "#EAB308" }
    icon { "coffee" }
    is_system { false }

    trait :system do
      is_system { true }
      user { nil }
    end

    trait :committed do
      name { "Comprometido" }
      code { "committed" }
      category_type { "committed" }
      color { "#EF4444" }
    end

    trait :discretionary do
      name { "Flexible" }
      code { "discretionary" }
      category_type { "discretionary" }
    end

    trait :income do
      name { "Ingreso" }
      code { "income" }
      category_type { "income" }
      color { "#06B6D4" }
    end
  end
end
