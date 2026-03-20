FactoryBot.define do
  factory :role do
    name { Faker::Job.title }
    sequence(:slug) { |n| "role-#{n}" }
    description { Faker::Lorem.sentence }
    active { true }

    trait :admin do
      name { 'Administrador' }
      slug { 'admin' }
    end

    trait :viewer do
      name { 'Viewer' }
      slug { 'viewer' }
    end
  end
end
