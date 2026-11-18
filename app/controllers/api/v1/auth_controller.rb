class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_request!, only: %i[login refresh]
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def login
    result = Auth::Interactors::LoginUser.new.call(email: params.require(:email), password: params.require(:password))
    render json: Auth::Presenters::AuthPresenter.user_with_tokens(**result)
  rescue Auth::Errors::InvalidCredentials, Auth::Errors::InvalidEmail
    render_unauthorized
  rescue Auth::Errors::NotAllowed
    render_not_allowed
  end

  def refresh
    result = Auth::Interactors::RefreshToken.new.call(user_id: params.require(:user_id), raw_refresh_token: params.require(:refresh_token))
    render json: Auth::Presenters::AuthPresenter.tokens(**result)
  rescue Auth::Errors::TokenReuse, Auth::Errors::InvalidToken
    render_unauthorized
  end

  def logout
    Auth::Interactors::LogoutUser.new.call(user_id: current_user.id)
    head :no_content
  end

  def me
    render json: Auth::Presenters::AuthPresenter.user(current_user)
  end

  private

  # TCW-8: el registro está cerrado; una cuenta fuera de ALLOWED_IDENTITIES recibe este rechazo.
  def render_not_allowed
    render json: { errors: [ { status: "403", code: "not_allowed", detail: "Esta cuenta no tiene acceso a Ascent" } ] }, status: :forbidden
  end
end
