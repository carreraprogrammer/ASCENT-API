FactoryBot.define do
  factory :user_milestone do
    user
    account { user.default_account }
    code    { "first_transaction" }
    metadata { {} }
    achieved_at { Time.current }
  end
end
