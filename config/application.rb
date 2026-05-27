require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module BoilerplateRailsApi
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
    config.autoload_paths << Rails.root.join("app/domains")

    require_relative "../app/middleware/error_capture_middleware"
    config.middleware.insert_after ActionDispatch::ShowExceptions, ErrorCaptureMiddleware
    config.middleware.use Rack::Attack

    # ActiveRecord::Encryption — tokens de Gmail cifrados en DB.
    # Claves cargadas desde env vars (Railway). Generadas con `rails db:encryption:init`.
    config.active_record.encryption.primary_key         = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key   = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
  end
end
