require 'rails_helper'

RSpec.describe Auth::Interactors::LoginWithGoogle do
  let(:user_repo) { instance_double(Auth::Repositories::UserRepository) }
  let(:interactor) { described_class.new(user_repo: user_repo) }

  let(:auth_hash) do
    OmniAuth::AuthHash.new({
      uid: 'google-uid-123',
      info: {
        email: 'user@gmail.com',
        name: 'Test User',
        image: 'https://example.com/avatar.jpg'
      }
    })
  end

  describe '#call' do
    it 'crea o encuentra el usuario con los datos de Google' do
      user = build(:user, google_uid: 'google-uid-123')
      allow(user_repo).to receive(:find_or_create_from_google).and_return(user)

      result = interactor.call(auth_hash: auth_hash)

      expect(result).to eq(user)
      expect(user_repo).to have_received(:find_or_create_from_google).with(
        google_uid: 'google-uid-123',
        email: 'user@gmail.com',
        name: 'Test User',
        avatar_url: 'https://example.com/avatar.jpg'
      )
    end

    it 'lanza Auth::Errors::InvalidEmail si Google no provee email' do
      auth_hash_sin_email = OmniAuth::AuthHash.new({
        uid: 'google-uid-123',
        info: { email: nil, name: 'Test', image: nil }
      })

      expect {
        interactor.call(auth_hash: auth_hash_sin_email)
      }.to raise_error(Auth::Errors::InvalidEmail)
    end
  end
end
