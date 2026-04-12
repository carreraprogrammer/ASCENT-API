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
  end
end
