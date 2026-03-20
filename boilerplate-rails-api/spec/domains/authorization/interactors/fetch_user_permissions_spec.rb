require 'rails_helper'

RSpec.describe Authorization::Interactors::FetchUserPermissions do
  let(:user) { create(:user) }
  let(:role) { create(:role) }
  let!(:permission) { create(:permission, resource: 'users', action: 'read') }

  it 'returns array of resource:action strings' do
    RolePermission.create!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    expect(described_class.new.call(user_id: user.id)).to eq([ 'users:read' ])
  end

  it 'returns empty array if the user has no roles' do
    expect(described_class.new.call(user_id: user.id)).to eq([])
  end

  it 'does not include permissions from expired roles' do
    RolePermission.create!(role: role, permission: permission)
    UserRole.create!(user: user, role: role, expires_at: 1.day.ago)
    expect(described_class.new.call(user_id: user.id)).to eq([])
  end
end
