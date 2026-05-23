FactoryBot.define do
  factory :account do
    owner_user factory: :user
    name { owner_user.name.presence || owner_user.email }
    sequence(:slug) { |n| "account-#{n}" }
    active { true }
    settings { {} }
  end
end
