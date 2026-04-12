module AuthHeaders
  def auth_headers_for(user)
    permissions = Authorization::Interactors::FetchUserPermissions.new.call(user_id: user.id)
    token = JwtService.encode_access_token(user_id: user.id, email: user.email, super_admin: user.super_admin, permissions: permissions)
    { 'Authorization' => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHeaders
end
