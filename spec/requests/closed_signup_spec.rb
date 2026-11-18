require "rails_helper"

# TCW-8: el registro está cerrado en la API. ALLOWED_IDENTITIES (email:<correo>, tcw:<sub del cerebro>) dice quién
# entra. Fuera de la lista: rechazo claro y ninguna fila nueva en users ni en accounts. Vacía: no entra nadie.
RSpec.describe "Registro cerrado (TCW-8)" do
  OWNER_EMAIL = "owner@example.com".freeze
  OWNER_SUB = "u_brain_owner".freeze

  around do |example|
    before = ENV["ALLOWED_IDENTITIES"]
    ENV["ALLOWED_IDENTITIES"] = allowed
    example.run
  ensure
    ENV["ALLOWED_IDENTITIES"] = before
  end

  let(:allowed) { "email:#{OWNER_EMAIL},tcw:#{OWNER_SUB}" }

  def google_web(email:, uid: "g-#{email}", verified: true)
    Rails.application.env_config["omniauth.auth"] = OmniAuth::AuthHash.new(
      uid: uid, info: { email: email, name: "X", image: nil }, extra: { raw_info: { email_verified: verified } }
    )
    get "/auth/google_oauth2/callback"
  ensure
    Rails.application.env_config.delete("omniauth.auth")
  end

  def google_mobile(email:, sub: "g-#{email}")
    allow_any_instance_of(Auth::Interactors::LoginWithGoogleToken).to receive(:google_profile_info)
      .and_return({ "sub" => sub, "email" => email, "email_verified" => true, "name" => "X" })
    post "/api/v1/auth/google/mobile", params: { access_token: "t" }
  end

  def tcw(sub:, email:)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    jwks = { "keys" => [ JWT::JWK.new(key, kid: "k1", alg: "ES256").export.transform_keys(&:to_s) ] }
    now = Time.now.to_i
    token = JWT.encode({ iss: "https://brain.test", sub: sub, aud: "ascent-web", iat: now, exp: now + 600,
                         email: email, email_verified: true }, key, "ES256", { kid: "k1" })
    http = ->(_verb, url, _form) { url.end_with?("/token") ? { "id_token" => token } : jwks }
    real = Auth::Interactors::LoginWithCyborgWay.new(http: http, issuer: "https://brain.test", client_id: "ascent-web")
    allow(Auth::Interactors::LoginWithCyborgWay).to receive(:new).and_return(real)
    post "/api/v1/auth/tcw", params: { code: "c", code_verifier: "v" * 43, redirect_uri: "https://ascent.test/cb" }
  end

  def counts = [ User.count, Account.count ]

  describe "una identidad fuera de la lista" do
    it "con Google (web) vuelve al login con not_allowed y no crea nada" do
      expect { google_web(email: "stranger@example.com") }.not_to change { counts }
      expect(response).to redirect_to(%r{/auth/callback\?error=not_allowed})
    end

    it "con Google (móvil) recibe 403 y no crea nada" do
      expect { google_mobile(email: "stranger@example.com") }.not_to change { counts }
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body).dig("errors", 0, "code")).to eq("not_allowed")
    end

    it "con The Cyborg Way recibe 403 y no crea nada" do
      expect { tcw(sub: "u_stranger", email: "stranger@example.com") }.not_to change { counts }
      expect(response).to have_http_status(:forbidden)
    end

    it "con correo y contraseña (cuenta existente fuera de la lista) recibe el mismo 401 con la contraseña buena o mala" do
      create(:user, email: "old@example.com")
      answers = %w[Password1 wrong-password].map do |password|
        post "/api/v1/auth/login", params: { email: "old@example.com", password: password }
        [ response.status, response.body ]
      end
      expect(answers.uniq.size).to eq(1)                 # no sirve para confirmar la contraseña de una cuenta ajena
      expect(answers.first.first).to eq(401)
    end

    it "no renueva la sesión de una cuenta que ya tenía refresh token" do
      user = create(:user, email: "old@example.com")
      raw = JwtService.encode_refresh_token
      Auth::Repositories::UserRepository.new.save_refresh_token(user_id: user.id, token_hash: BCrypt::Password.create(raw),
                                                                expires_at: 1.day.from_now)
      post "/api/v1/auth/refresh", params: { user_id: user.id, refresh_token: raw }
      expect(response).to have_http_status(:unauthorized)
    end

    it "con Google y el correo del dueño sin verificar no entra" do
      expect { google_web(email: OWNER_EMAIL, verified: false) }.not_to change { counts }
      expect(response).to redirect_to(%r{error=invalid_email})
    end
  end

  context "con la variable vacía" do
    let(:allowed) { "" }

    it "no entra nadie nuevo y no se crea nada" do
      expect { google_web(email: OWNER_EMAIL) }.not_to change { counts }
      expect(response).to redirect_to(%r{error=not_allowed})
      expect { google_mobile(email: OWNER_EMAIL) }.not_to change { counts }
      expect(response).to have_http_status(:forbidden)
      expect { tcw(sub: OWNER_SUB, email: OWNER_EMAIL) }.not_to change { counts }
      expect(response).to have_http_status(:forbidden)
    end

    it "tampoco entra una cuenta que ya existía" do
      create(:user, email: OWNER_EMAIL)
      post "/api/v1/auth/login", params: { email: OWNER_EMAIL, password: "Password1" }
      expect(response).to have_http_status(:unauthorized)
      google_web(email: OWNER_EMAIL)
      expect(response).to redirect_to(%r{error=not_allowed})
    end
  end

  describe "el dueño sigue entrando" do
    let!(:owner) { create(:user, email: OWNER_EMAIL) }

    it "con Google (web)" do
      expect { google_web(email: OWNER_EMAIL) }.not_to change(User, :count)
      expect(response).to redirect_to(%r{/auth/callback\?access_token=})
    end

    it "con Google (móvil)" do
      google_mobile(email: OWNER_EMAIL)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "id")).to eq(owner.id)
    end

    it "con The Cyborg Way por su sub, aunque el token traiga otro correo (el noreply de GitHub)" do
      owner.update!(tcw_sub: OWNER_SUB)
      expect { tcw(sub: OWNER_SUB, email: "123+owner@users.noreply.github.com") }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "id")).to eq(owner.id)
    end

    it "con correo y contraseña, y renueva su sesión" do
      post "/api/v1/auth/login", params: { email: OWNER_EMAIL, password: "Password1" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      post "/api/v1/auth/refresh", params: { user_id: owner.id, refresh_token: body.dig("meta", "refresh_token") }
      expect(response).to have_http_status(:ok)
    end
  end

  it "la ruta de registro responde 404" do
    post "/api/v1/auth/register", params: { email: "x@example.com", password: "Password1", name: "X" }
    expect(response).to have_http_status(:not_found)
  end

  it "la demo sigue abriendo sin crear cuentas, también con la lista vacía" do
    ENV["ALLOWED_IDENTITIES"] = ""
    AgentType.create!(name: "Finance Coach", slug: "finance_coach")
    Demo::Interactors::ResetDemoAccount.new.call                      # el reset nocturno siembra la cuenta demo
    expect { post "/api/v1/demo/session" }.not_to change { counts }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("data", "attributes", "demo")).to be(true)
  end
end
