Rails.application.routes.draw do
  mount Rswag::Api::Engine => "/api-docs"
  mount Rswag::Ui::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      post "auth/register", to: "auth#register"
      post "auth/login", to: "auth#login"
      post "auth/refresh", to: "auth#refresh"
      delete "auth/logout", to: "auth#logout"
      get "auth/me", to: "auth#me"

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
