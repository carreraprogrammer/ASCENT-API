Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    configured_origins = ENV.fetch("ALLOWED_ORIGINS", ENV.fetch("FRONTEND_URL", "http://localhost:3000")).split(",")
    mobile_origins = [
      "capacitor://localhost",
      "ionic://localhost"
    ]
    local_origins = [
      "http://localhost:3000",
      "http://localhost:5173"
    ]
    origins_list = [
      ENV.fetch("FRONTEND_URL", "http://localhost:3000"),
      *configured_origins,
      *mobile_origins,
      *local_origins
    ]

    origins(*origins_list.map(&:strip).uniq)
    resource "*", headers: :any, methods: %i[get post put patch delete options head]
  end
end
