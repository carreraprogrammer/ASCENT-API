require 'rails_helper'

RSpec.describe 'Forms API' do
  let!(:schema) { create(:form_schema, slug: 'login-form') }
  describe 'GET /api/v1/form_schemas/:slug' do
    it 'returns the schema without authentication' do
      get '/api/v1/form_schemas/login-form'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig('data', 'id')).to eq('login-form')
      expect(json.dig('data', 'type')).to eq('form_schemas')
      expect(json.dig('data', 'attributes', 'fields')).to be_an(Array)
    end
    it 'returns 404 for unknown slug' do
      get '/api/v1/form_schemas/nonexistent'
      expect(response).to have_http_status(:not_found)
    end
  end
  describe 'POST /api/v1/form_schemas' do
    it 'returns 401 without token' do
      post '/api/v1/form_schemas', params: {}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
