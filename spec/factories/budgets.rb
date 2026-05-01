FactoryBot.define do
  factory :budget do
    user
    category
    subcategory
    amount_limit { 200_000 }
    month { Date.current.month }
    year { Date.current.year }
  end
end
