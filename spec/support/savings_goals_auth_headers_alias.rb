module SavingsGoalsAuthHeadersAlias
  def auth_headers(user)
    auth_headers_for(user)
  end
end

RSpec.configure do |config|
  config.include SavingsGoalsAuthHeadersAlias
end
