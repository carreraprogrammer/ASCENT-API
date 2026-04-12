Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("ALLOWED_ORIGINS", ENV.fetch("FRONTEND_URL", "http://localhost:3000")).split(","))
    resource "*", headers: :any, methods: %i[get post put patch delete options head]
  end
end
