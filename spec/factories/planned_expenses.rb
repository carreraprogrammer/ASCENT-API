FactoryBot.define do
  factory :planned_expense do
    user
    account { user.default_account }
    category
    subcategory { create(:subcategory, category: category) }
    name { "SOAT moto" }
    amount_estimated { 420_000 }
    target_date { Date.current + 3.months }
    planning_type { "mandatory_one_off" }
    status { "planned" }
    notes { "Renovacion anual estimada" }
  end
end
