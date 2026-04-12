require 'rails_helper'

RSpec.describe Authorization::Interactors::AssignRoleToUser do
  let(:user) { create(:user) }
  let!(:role) { create(:role, slug: 'editor') }

  it 'assigns the role correctly' do
    result = described_class.new.call(user_id: user.id, role_slug: 'editor')
    expect(result.slug).to eq('editor')
    expect(UserRole.find_by(user_id: user.id, role_id: role.id)).to be_present
  end

  it 'raises error if the role does not exist' do
    expect { described_class.new.call(user_id: user.id, role_slug: 'missing') }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'is idempotent' do
    described_class.new.call(user_id: user.id, role_slug: 'editor')
    expect { described_class.new.call(user_id: user.id, role_slug: 'editor') }.not_to change(UserRole, :count)
  end
end
