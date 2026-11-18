module Auth
  module Interactors
    # "Continuar con The Cyborg Way" (TCW-1 fase 4): el cerebro de The Cyborg Way como proveedor de identidad.
    #
    # La web hace OIDC + PKCE contra el cerebro y manda aquí el code, su code_verifier y el redirect_uri.
    # Este interactor:
    #   1. cambia el code por tokens en el endpoint /token del cerebro (cliente público ascent-web, PKCE);
    #   2. verifica el ID token con el JWKS del cerebro: ES256, iss = el cerebro, aud = ascent-web, exp;
    #   3. exige el correo verificado y la persona en ALLOWED_IDENTITIES (TCW-8), y vincula la cuenta existente con ese correo (o crea una).
    # No guarda los tokens del cerebro: solo el sub, para reconocer a la persona la próxima vez.
    class LoginWithCyborgWay
      def initialize(user_repo: Repositories::UserRepository.new, http: nil, issuer: nil, client_id: nil,
                     allowed: ValueObjects::AllowedIdentities.from_env)
        @user_repo = user_repo
        @allowed = allowed
        @http = http || method(:post_and_get)
        @issuer = issuer || ENV.fetch("BRAIN_ISSUER", "https://thecyborgway.dev")
        @client_id = client_id || ENV.fetch("TCW_OIDC_CLIENT_ID", "ascent-web")
      end

      def call(code:, code_verifier:, redirect_uri:)
        raise Auth::Errors::Unauthorized, "Faltan code, code_verifier o redirect_uri" if [ code, code_verifier, redirect_uri ].any?(&:blank?)

        tokens = @http.call(:post, "#{@issuer}/token", {
          grant_type: "authorization_code", code: code, code_verifier: code_verifier,
          redirect_uri: redirect_uri, client_id: @client_id
        })
        id_token = tokens["id_token"]
        raise Auth::Errors::Unauthorized, "El cerebro no devolvió un ID token" if id_token.blank?

        claims = verify(id_token)
        raise Auth::Errors::InvalidEmail, "El correo no está verificado" unless claims["email_verified"] == true && claims["email"].present?
        @allowed.check!(email: claims["email"], tcw_sub: claims["sub"])   # TCW-8: antes de buscar o crear

        @user_repo.find_or_create_from_cyborg_way(sub: claims["sub"], email: claims["email"])
      end

      private

      def verify(id_token)
        jwks = @http.call(:get, "#{@issuer}/.well-known/jwks.json", nil)
        payload, = JWT.decode(id_token, nil, true, algorithms: [ "ES256" ], jwks: { keys: jwks["keys"] },
                              iss: @issuer, verify_iss: true, aud: @client_id, verify_aud: true,
                              required_claims: %w[sub exp iat])
        payload
      rescue JWT::DecodeError => e
        raise Auth::Errors::Unauthorized, "ID token inválido: #{e.class.name.demodulize}"
      end

      def post_and_get(verb, url, form)
        uri = URI(url)
        request = verb == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
        request.set_form_data(form) if form
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
          http.request(request)
        end
        raise Auth::Errors::Unauthorized, "El cerebro rechazó el inicio de sesión" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
