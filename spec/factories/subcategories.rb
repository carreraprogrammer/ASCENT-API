FactoryBot.define do
  factory :subcategory do
    category
    name { Faker::Commerce.product_name }
    sequence(:code) { |n| "subcategory_#{n}" }
    is_system { false }

    trait :system do
      is_system { true }
    end
  end
end
