require 'rails_helper'

RSpec.describe Authorization::Policies::UserPolicy do
  let(:record) { create(:user) }

  it 'super_admin can do everything' do
    user = create(:user, super_admin: true)
    context = Authorization::UserContext.new(user: user, permissions: [])
    policy = described_class.new(context, record)
    expect(policy.index?).to be(true)
    expect(policy.show?).to be(true)
    expect(policy.update?).to be(true)
    expect(policy.destroy?).to be(true)
  end

  it 'user with users:read can index and show' do
    user = create(:user)
    context = Authorization::UserContext.new(user: user, permissions: [ 'users:read' ])
    policy = described_class.new(context, record)
    expect(policy.index?).to be(true)
    expect(policy.show?).to be(true)
  end

  it 'user without permissions cannot do anything' do
    user = create(:user)
    context = Authorization::UserContext.new(user: user, permissions: [])
    policy = described_class.new(context, record)
    expect(policy.index?).to be(false)
    expect(policy.show?).to be(false)
    expect(policy.create?).to be(false)
    expect(policy.destroy?).to be(false)
  end
end
