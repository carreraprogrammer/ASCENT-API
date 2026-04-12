resources = %w[users roles permissions form_schemas]
actions = %w[read create update destroy manage]

resources.each do |resource|
  actions.each do |action|
    next if action == 'manage' && resource != 'users'
    Permission.find_or_create_by!(resource: resource, action: action) do |p|
      p.description = "Puede #{action} #{resource}"
    end
  end
end

admin_role = Role.find_or_create_by!(slug: 'admin') do |r|
  r.name = 'Administrador'
  r.description = 'Acceso completo al sistema'
end
editor_role = Role.find_or_create_by!(slug: 'editor') do |r|
  r.name = 'Editor'
  r.description = 'Puede gestionar contenido pero no usuarios ni roles'
end
viewer_role = Role.find_or_create_by!(slug: 'viewer') do |r|
  r.name = 'Viewer'
  r.description = 'Solo lectura'
end

admin_role.permissions = Permission.all
editor_role.permissions = Permission.where(resource: 'form_schemas')
viewer_role.permissions = Permission.where(action: 'read')

super_admin = User.find_or_create_by!(email: 'superadmin@boilerplate.dev') do |u|
  u.encrypted_password = BCrypt::Password.create('Admin1234!')
  u.name = 'Super Admin'
  u.super_admin = true
end

admin_user = User.find_or_create_by!(email: 'admin@boilerplate.dev') do |u|
  u.encrypted_password = BCrypt::Password.create('Admin1234!')
  u.name = 'Admin User'
  u.super_admin = false
end
UserRole.find_or_create_by!(user: admin_user, role: admin_role)

viewer_user = User.find_or_create_by!(email: 'viewer@boilerplate.dev') do |u|
  u.encrypted_password = BCrypt::Password.create('Viewer1234!')
  u.name = 'Viewer User'
  u.super_admin = false
end
UserRole.find_or_create_by!(user: viewer_user, role: viewer_role)

forms = [
  { slug: 'login-form', title: 'Sign In', submit_label: 'Sign In', submit_endpoint: '/api/v1/auth/login', submit_method: 'POST', fields: [
    { 'name' => 'email', 'label' => 'Email address', 'type' => 'email', 'placeholder' => 'you@example.com', 'required' => true, 'order' => 1, 'validations' => { 'format' => 'email', 'max_length' => 255 } },
    { 'name' => 'password', 'label' => 'Password', 'type' => 'password', 'placeholder' => '********', 'required' => true, 'order' => 2, 'validations' => { 'min_length' => 8 } }
  ] },
  { slug: 'register-form', title: 'Create Account', submit_label: 'Create Account', submit_endpoint: '/api/v1/auth/register', submit_method: 'POST', fields: [
    { 'name' => 'name', 'label' => 'Full name', 'type' => 'text', 'placeholder' => 'Your name', 'required' => true, 'order' => 1, 'validations' => { 'min_length' => 2, 'max_length' => 100 } },
    { 'name' => 'email', 'label' => 'Email address', 'type' => 'email', 'placeholder' => 'you@example.com', 'required' => true, 'order' => 2, 'validations' => { 'format' => 'email', 'max_length' => 255 } },
    { 'name' => 'password', 'label' => 'Password', 'type' => 'password', 'placeholder' => 'Min. 8 characters', 'required' => true, 'order' => 3, 'validations' => { 'min_length' => 8 } },
    { 'name' => 'password_confirmation', 'label' => 'Confirm password', 'type' => 'password', 'placeholder' => 'Repeat your password', 'required' => true, 'order' => 4, 'validations' => { 'min_length' => 8 } }
  ] },
  { slug: 'profile-form', title: 'Edit Profile', submit_label: 'Save Changes', submit_endpoint: '/api/v1/auth/me', submit_method: 'PATCH', fields: [
    { 'name' => 'name', 'label' => 'Full name', 'type' => 'text', 'placeholder' => 'Your name', 'required' => true, 'order' => 1, 'validations' => { 'min_length' => 2, 'max_length' => 100 } },
    { 'name' => 'bio', 'label' => 'Bio', 'type' => 'textarea', 'placeholder' => 'Tell us about yourself', 'required' => false, 'order' => 2, 'rows' => 4, 'validations' => { 'max_length' => 500 } },
    { 'name' => 'phone', 'label' => 'Phone number', 'type' => 'tel', 'placeholder' => '+57 300 000 0000', 'required' => false, 'order' => 3, 'validations' => { 'format' => 'phone' } },
    { 'name' => 'birth_date', 'label' => 'Date of birth', 'type' => 'date', 'required' => false, 'order' => 4 }
  ] }
]
forms.each do |attrs|
  FormSchema.find_or_create_by!(slug: attrs[:slug]) do |f|
    f.title = attrs[:title]
    f.submit_label = attrs[:submit_label]
    f.submit_endpoint = attrs[:submit_endpoint]
    f.submit_method = attrs[:submit_method]
    f.fields = JSON.generate(attrs[:fields])
    f.active = true
  end
end
puts "Seeded: #{FormSchema.count} form schemas"
