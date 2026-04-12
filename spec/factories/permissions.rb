FactoryBot.define do
  factory :permission do
    resource { %w[users roles forms].sample }
    action { %w[read create update destroy].sample }

    trait :users_read do
      resource { 'users' }
      action { 'read' }
    end

    trait :roles_create do
      resource { 'roles' }
      action { 'create' }
    end
  end
end
