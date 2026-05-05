require 'rails_helper'

RSpec.describe Auth::Interactors::LoginWithGoogleToken do
  let(:user_repo) { instance_double(Auth::Repositories::UserRepository) }
  let(:interactor) { described_class.new(user_repo: user_repo) }
  let(:user) { build(:user, google_uid: 'google-uid-123') }
  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(user_repo).to receive(:find_or_create_from_google).and_return(user)
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  describe '#call' do
    it 'usa access_token para consultar el perfil de Google' do
      allow(http).to receive(:request).and_return(ok_response({
        sub: 'google-uid-123',
        email: 'user@gmail.com',
        name: 'Test User',
        picture: 'https://example.com/avatar.jpg'
      }))

      result = interactor.call(access_token: 'google-access-token')

      expect(result).to eq(user)
      expect(user_repo).to have_received(:find_or_create_from_google).with(
        google_uid: 'google-uid-123',
        email: 'user@gmail.com',
        name: 'Test User',
        avatar_url: 'https://example.com/avatar.jpg'
      )
    end

    it 'intercambia server_auth_code y usa el id_token para leer el perfil' do
      stub_google_env
      allow(http).to receive(:request).and_return(
        ok_response({ id_token: 'google-id-token' }),
        ok_response({
          sub: 'google-uid-123',
          aud: 'web-client-id',
          email: 'user@gmail.com',
          name: 'Test User',
          picture: 'https://example.com/avatar.jpg'
        })
      )

      result = interactor.call(server_auth_code: 'server-auth-code')

      expect(result).to eq(user)
      expect(http).to have_received(:request).with(
        satisfy do |request|
          request.is_a?(Net::HTTP::Post) &&
            request.body.include?('code=server-auth-code') &&
            request.body.include?('client_id=web-client-id') &&
            request.body.include?('client_secret=client-secret') &&
            request.body.include?('grant_type=authorization_code')
        end
      )
      expect(user_repo).to have_received(:find_or_create_from_google).with(
        google_uid: 'google-uid-123',
        email: 'user@gmail.com',
        name: 'Test User',
        avatar_url: 'https://example.com/avatar.jpg'
      )
    end

    it 'rechaza id_token con audiencia inesperada' do
      stub_google_env
      allow(http).to receive(:request).and_return(ok_response({
        sub: 'google-uid-123',
        aud: 'other-client-id',
        email: 'user@gmail.com'
      }))

      expect {
        interactor.call(id_token: 'google-id-token')
      }.to raise_error(Auth::Errors::Unauthorized)
    end

    it 'lanza Auth::Errors::InvalidEmail si Google no provee email' do
      allow(http).to receive(:request).and_return(ok_response({
        sub: 'google-uid-123',
        name: 'Test User'
      }))

      expect {
        interactor.call(access_token: 'google-access-token')
      }.to raise_error(Auth::Errors::InvalidEmail)
    end
  end

  def ok_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return(body.to_json)
    response
  end

  def stub_google_env
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('web-client-id')
    allow(ENV).to receive(:[]).with('GOOGLE_SERVER_CLIENT_ID').and_return(nil)
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_SECRET').and_return('client-secret')
    allow(ENV).to receive(:[]).with('GOOGLE_IOS_CLIENT_ID').and_return(nil)
    allow(ENV).to receive(:[]).with('GOOGLE_OAUTH_REDIRECT_URI').and_return('')
  end
end
