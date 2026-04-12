Rails.application.routes.draw do
  # OAuth — fuera del namespace api/v1 porque OmniAuth maneja sus propias rutas
  get "/auth/google_oauth2/callback", to: "api/v1/oauth#google_callback"
  get "/auth/failure", to: "api/v1/oauth#failure"

  mount Rswag::Api::Engine => "/api-docs"
  mount Rswag::Ui::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      get "auth/google", to: redirect("/auth/google_oauth2")
      post "auth/register", to: "auth#register"
      post "auth/login", to: "auth#login"
      post "auth/refresh", to: "auth#refresh"
      delete "auth/logout", to: "auth#logout"
      get "auth/me", to: "auth#me"
      get "forms/:slug", to: "forms#show"

      resources :form_schemas, controller: "forms", param: :slug, only: [ :index, :show, :create, :update, :destroy ]
      resources :roles, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :assign_permission
          delete :revoke_permission
        end
      end
      resources :users, only: [ :index, :show, :update, :destroy ] do
        member do
          post :assign_role
          delete :revoke_role
        end
      end
    end
  end
end
