require 'rails_helper'

RSpec.describe Auth::Interactors::RegisterUser do
  subject(:interactor) { described_class.new }
  let(:valid_params) { { email: 'new@example.com', password: 'Password1', name: 'Daniel' } }
  it 'creates a user and returns tokens' do
    result = interactor.call(**valid_params)
    expect(result[:user]).to be_a(Auth::Entities::User)
    expect(result[:access_token]).to be_present
    expect(result[:refresh_token]).to be_present
  end
  it 'raises InvalidEmail if email already taken' do
    create(:user, email: 'new@example.com')
    expect { interactor.call(**valid_params) }.to raise_error(Auth::Errors::InvalidEmail)
  end
  it 'raises WeakPassword if password is too simple' do
    expect { interactor.call(**valid_params.merge(password: 'simple')) }.to raise_error(Auth::Errors::WeakPassword)
  end
end
