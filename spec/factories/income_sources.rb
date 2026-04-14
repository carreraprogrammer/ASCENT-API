FactoryBot.define do
  factory :income_source do
    user
    name              { "EMAPTA" }
    expected_day_from { 1 }
    expected_day_to   { 5 }
    expected_amount   { 3_335_000 }
    is_variable       { false }
    active            { true }

    trait :variable do
      name        { "525" }
      is_variable { true }
      expected_day_from { 25 }
      expected_day_to   { 28 }
      expected_amount   { 3_000_000 }
    end

    trait :inactive do
      active { false }
    end
  end
end
