FactoryBot.define do
  factory :form_schema do
    sequence(:slug) { |n| "test-form-#{n}" }
    title { 'Test Form' }
    submit_label { 'Submit' }
    submit_endpoint { '/api/v1/auth/login' }
    submit_method { 'POST' }
    active { true }
    fields do
      JSON.generate([ { 'name' => 'email', 'label' => 'Email', 'type' => 'email', 'required' => true, 'order' => 1 } ])
    end
  end
end
