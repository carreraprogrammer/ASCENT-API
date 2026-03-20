class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_request!, only: %i[register login refresh]
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def register
    result = Auth::Interactors::RegisterUser.new.call(email: params.require(:email), password: params.require(:password), name: params.require(:name))
    render json: Auth::Presenters::AuthPresenter.user_with_tokens(**result), status: :created
  rescue Auth::Errors::InvalidEmail, Auth::Errors::WeakPassword => e
    render_unprocessable(e.message)
  end

  def login
    result = Auth::Interactors::LoginUser.new.call(email: params.require(:email), password: params.require(:password))
    render json: Auth::Presenters::AuthPresenter.user_with_tokens(**result)
  rescue Auth::Errors::InvalidCredentials, Auth::Errors::InvalidEmail
    render_unauthorized
  end

  def refresh
    result = Auth::Interactors::RefreshToken.new.call(user_id: params.require(:user_id), raw_refresh_token: params.require(:refresh_token))
    render json: Auth::Presenters::AuthPresenter.tokens(**result)
  rescue Auth::Errors::TokenReuse, Auth::Errors::InvalidToken
    render_unauthorized
  end

  def logout
    Auth::Repositories::UserRepository.new.invalidate_refresh_token(user_id: current_user.id)
    head :no_content
  end

  def me
    entity = Auth::Repositories::UserRepository.new.find_by_id(current_user.id)
    render json: Auth::Presenters::AuthPresenter.user(entity)
  end
end
