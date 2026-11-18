require 'rails_helper'

# TCW-8: el registro está cerrado. La ruta de registro ya no existe y no crea a nadie.
RSpec.describe 'POST /api/v1/auth/register' do
  it 'answers 404 and makes no user' do
    expect {
      post '/api/v1/auth/register', params: { email: 'new@example.com', password: 'Password1', name: 'Daniel' }
    }.not_to change(User, :count)
    expect(response).to have_http_status(:not_found)
  end
end
