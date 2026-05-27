Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "rails/health#show"

  # OAuth — fuera del namespace api/v1 porque OmniAuth maneja sus propias rutas
  get "/auth/google_oauth2/callback", to: "api/v1/oauth#google_callback"
  get "/auth/failure", to: "api/v1/oauth#failure"

  mount Rswag::Api::Engine => "/api-docs"
  mount Rswag::Ui::Engine => "/api-docs"

  namespace :api do
    namespace :v1 do
      get "auth/google", to: redirect("/auth/google_oauth2")
      post "auth/google/mobile", to: "oauth#google_mobile_callback"
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

      # Finanzas — Core
      resources :categories, only: [ :index, :create, :destroy ]
      resources :subcategories, only: [ :create ]
      resources :transactions, only: [ :index, :create, :update, :destroy ] do
        collection do
          get :pending
          get :needs_review
          get :credit_card_pending
          get :balance
          post :batch
          post :settle_credit_card
        end
      end

      # Finanzas — Fase 2
      get   "financial_context", to: "financial_contexts#show"
      patch "financial_context", to: "financial_contexts#update"

      resources :debts,                only: [ :index, :create, :update, :destroy ] do
        member do
          post :payments
        end
      end
      resources :budgets,              only: [ :index, :create, :update ]
      resources :monthly_plans,        only: [ :index, :update ] do
        collection do
          get :current
          get :propose
          get :wizard_data
          post :generate
        end
        member do
          post :confirm
          post :close
        end
      end
      resources :income_sources,       only: [ :index, :create, :update, :destroy ]
      resources :recurring_obligations, only: [ :index, :create, :update, :destroy ]
      resources :planned_expenses,     only: [ :index, :create, :update ]
      resources :savings_goals,        only: [ :index, :create, :update, :destroy ]
      resources :sinking_funds, only: [ :index, :create, :update, :destroy ] do
        member do
          post :withdraw
        end
      end
      resources :milestones,           only: [ :index, :create ]

      resources :pending_actions, only: [ :create, :update ] do
        collection do
          get :active
        end
      end

      get "completeness", to: "completeness#show"
      post "agents/preflight", to: "agents#preflight"
      post "agents/chat",      to: "agents#chat"

      # Agent UI Events — canal agente → front-end
      get  "agent_events/pending", to: "agent_ui_events#pending"
      post "agent_events",         to: "agent_ui_events#create"
      patch "agent_events/:id/consume", to: "agent_ui_events#consume"

      # Análisis nocturno polimórfico
      post  "night_analyses",          to: "night_analyses#create"
      get   "night_analyses",          to: "night_analyses#index"
      get   "night_analyses/metrics",  to: "night_analyses#metrics"
      get   "night_analyses/:date",    to: "night_analyses#show",  constraints: { date: /\d{4}-\d{2}-\d{2}/ }

      # Agent Insights — capa de coaching ligada a un análisis
      get   "agent_insights/latest", to: "agent_insights#latest"
      patch "agent_insights/:id",    to: "agent_insights#update_status"

      resources :chat_messages, only: [ :index, :create ]

      get "summary",        to: "summary#show"
      get "budget_context", to: "budget_context#show"

      # Gmail OAuth — Fase 0.6
      post   "auth/gmail",                    to: "gmail_oauth#start"
      get    "auth/gmail/callback",           to: "gmail_oauth#callback"
      get    "me/email_connection",           to: "gmail_oauth#status"
      delete "me/email_connection",           to: "gmail_oauth#disconnect"
      get    "me/email_connection/token",     to: "gmail_oauth#token"

      # Gamificación — Track A
      get  "me/progress",                to: "progress#show"
      get  "me/features",                to: "progress#features"
      post "me/features/:key/unlock",    to: "progress#unlock"

      # Admin — solo super_admin
      get  "admin/accounts",     to: "admin#accounts"
      post "admin/impersonate",  to: "admin#impersonate"

      # Agent internals — solo service account, sin X-Account-Id
      get "agent/accounts/active", to: "agent#active_accounts"

      # Telegram (sin autenticación JWT — Telegram llama directamente)
      post "telegram/webhook", to: "telegram#webhook"
      get  "telegram/updates", to: "telegram#updates"
    end
  end
end
