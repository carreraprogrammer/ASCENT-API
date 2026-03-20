FactoryBot.define do
  factory :user do
    email { Faker::Internet.unique.email }
    name { Faker::Name.name }
    encrypted_password { BCrypt::Password.create('Password1') }
    confirmed_at { nil }
    super_admin { false }

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :with_refresh_token do
      refresh_token_hash { BCrypt::Password.create('sample_token') }
      refresh_token_expires_at { 30.days.from_now }
    end
  end
end
