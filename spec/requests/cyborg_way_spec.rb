require "rails_helper"

# TCW-1 fase 4: "Continuar con The Cyborg Way". Un emisor simulado local (llave EC de prueba y su JWKS) hace de
# cerebro: el interactor cambia el code, verifica el ID token y vincula la cuenta por correo verificado.
RSpec.describe "Continuar con The Cyborg Way" do
  let(:issuer) { "https://brain.test" }
  let(:key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:jwk) { JWT::JWK.new(key, kid: "k1", alg: "ES256") }
  let(:jwks) { { "keys" => [ jwk.export.transform_keys(&:to_s) ] } }

  def id_token(claims = {}, signing_key: key, kid: "k1")
    now = Time.now.to_i
    payload = { iss: issuer, sub: "u_brain_owner", aud: "ascent-web", iat: now, exp: now + 600,
                email: "owner@example.com", email_verified: true }.merge(claims)
    JWT.encode(payload, signing_key, "ES256", { kid: kid })
  end

  def login_with(token, seen: [])
    http = lambda do |verb, url, form|
      seen << [ verb, url, form ]
      url.end_with?("/token") ? { "id_token" => token, "access_token" => "x" } : jwks
    end
    Auth::Interactors::LoginWithCyborgWay.new(http: http, issuer: issuer, client_id: "ascent-web")
      .call(code: "c", code_verifier: "v" * 43, redirect_uri: "https://ascent.test/auth/tcw/callback")
  end

  it "links the existing account that has the same verified email" do
    existing = User.create!(email: "owner@example.com", name: "Owner", confirmed_at: Time.current)
    seen = []
    user = login_with(id_token, seen: seen)
    expect(user.id).to eq(existing.id)
    expect(existing.reload.tcw_sub).to eq("u_brain_owner")
    post_form = seen.find { |verb, _, _| verb == :post }.last
    expect(post_form).to include(grant_type: "authorization_code", code_verifier: "v" * 43, client_id: "ascent-web")
  end

  it "recognises the person by sub on the next sign-in" do
    login_with(id_token)
    again = login_with(id_token(email: "renamed@example.com"))
    expect(User.where(tcw_sub: "u_brain_owner").count).to eq(1)
    expect(again.email).to eq("owner@example.com")
  end

  it "refuses an unverified email" do
    expect { login_with(id_token(email_verified: false)) }.to raise_error(Auth::Errors::InvalidEmail)
  end

  {
    "another issuer" => { iss: "https://evil.test" },
    "another audience" => { aud: "someone-else" },
    "an expired token" => { exp: Time.now.to_i - 10 }
  }.each do |name, claims|
    it "refuses #{name}" do
      expect { login_with(id_token(claims)) }.to raise_error(Auth::Errors::Unauthorized)
    end
  end

  it "refuses a token signed with another key" do
    other = OpenSSL::PKey::EC.generate("prime256v1")
    expect { login_with(id_token({}, signing_key: other)) }.to raise_error(Auth::Errors::Unauthorized)
  end

  it "answers the app with Ascent's own tokens" do
    allow(Auth::Interactors::LoginWithCyborgWay).to receive(:new).and_return(
      instance_double(Auth::Interactors::LoginWithCyborgWay, call: Auth::Repositories::UserRepository.new
        .find_or_create_from_cyborg_way(sub: "u_brain_owner", email: "owner@example.com"))
    )
    post "/api/v1/auth/tcw", params: { code: "c", code_verifier: "v", redirect_uri: "https://ascent.test/cb" }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("data", "attributes", "email")).to eq("owner@example.com")
    expect(body.dig("meta", "access_token")).to be_present
  end

  it "answers 401 when the brain does not confirm the sign-in" do
    allow(Auth::Interactors::LoginWithCyborgWay).to receive(:new).and_return(
      instance_double(Auth::Interactors::LoginWithCyborgWay).tap do |double|
        allow(double).to receive(:call).and_raise(Auth::Errors::Unauthorized, "no")
      end
    )
    post "/api/v1/auth/tcw", params: { code: "c", code_verifier: "v", redirect_uri: "https://ascent.test/cb" }
    expect(response).to have_http_status(:unauthorized)
  end
end
