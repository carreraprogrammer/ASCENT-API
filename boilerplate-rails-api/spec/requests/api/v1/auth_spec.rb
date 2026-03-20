require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/register' do
  it 'returns 201 with user data and tokens' do
    post '/api/v1/auth/register', params: { email: 'new@example.com', password: 'Password1', name: 'Daniel' }
    expect(response).to have_http_status(:created)
    json = JSON.parse(response.body)
    expect(json.dig('data', 'type')).to eq('users')
    expect(json.dig('meta', 'access_token')).to be_present
    expect(json.dig('meta', 'refresh_token')).to be_present
  end

  it 'returns 422 if email already exists' do
    create(:user, email: 'existing@example.com')
    post '/api/v1/auth/register', params: { email: 'existing@example.com', password: 'Password1', name: 'Daniel' }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
