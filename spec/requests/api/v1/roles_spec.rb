require 'rails_helper'

RSpec.describe 'Roles API' do
  let!(:role) { create(:role, :admin) }
  let(:user) { create(:user) }

  describe 'GET /api/v1/roles' do
    it 'returns 200 with correct permission' do
      permission = create(:permission, resource: 'roles', action: 'read')
      readable_role = create(:role, slug: 'reader-role')
      RolePermission.create!(role: readable_role, permission: permission)
      UserRole.create!(user: user, role: readable_role)
      get '/api/v1/roles', headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok)
    end

    it 'returns 403 without permission' do
      get '/api/v1/roles', headers: auth_headers_for(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 401 without token' do
      get '/api/v1/roles'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
