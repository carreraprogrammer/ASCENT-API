FactoryBot.define do
  factory :income_source do
    user
    name              { "EMAPTA" }
    expected_day_from { 1 }
    expected_day_to   { 5 }
    expected_amount   { 3_335_000 }
    is_variable       { false }
    classification    { "base" }
    cadence           { "monthly" }
    reliability_score { 90 }
    active            { true }
    notes             { nil }

    trait :variable do
      name        { "525" }
      is_variable { true }
      classification { "variable" }
      expected_day_from { 25 }
      expected_day_to   { 28 }
      expected_amount   { 3_000_000 }
    end

    trait :inactive do
      active { false }
    end
  end

  factory :income_source_schedule do
    income_source
    ordinal           { 1 }
    label             { "default" }
    expected_day_from { 1 }
    expected_day_to   { 5 }
    expected_amount   { 3_335_000 }
  end
end
