# ─── Finanzas: categorías del sistema ───────────────────────────────────────

SYSTEM_CATEGORIES = [
  {
    name: "Comprometido", code: "committed", category_type: "committed",
    color: "#C0392B", icon: "lockClosedOutline",
    subcategories: [
      { name: "Arriendo",           code: "arriendo",          icon: "homeOutline" },
      { name: "Créditos",           code: "creditos",          icon: "cardOutline" },
      { name: "Seguros",            code: "seguros",           icon: "shieldOutline" },
      { name: "Servicios públicos", code: "servicios_publicos", icon: "flashOutline" },
      { name: "Colegiaturas",       code: "colegiaturas",      icon: "schoolOutline" }
    ]
  },
  {
    name: "Necesario", code: "necessary", category_type: "necessary",
    color: "#D4732A", icon: "cartOutline",
    subcategories: [
      { name: "Mercado",    code: "mercado",    icon: "cartOutline" },
      { name: "Gasolina",   code: "gasolina",   icon: "carOutline" },
      { name: "Transporte", code: "transporte", icon: "busOutline" },
      { name: "Salud",       code: "salud",       icon: "heartOutline" },
      { name: "Ejercicio",   code: "ejercicio",   icon: "barbellOutline" },
      { name: "Celular",     code: "celular",     icon: "phonePortraitOutline" },
      { name: "Herramientas", code: "herramientas", icon: "constructOutline" }
    ]
  },
  {
    name: "Flexible", code: "discretionary", category_type: "discretionary",
    color: "#14B8A6", icon: "pricetagOutline",
    subcategories: [
      { name: "Restaurantes",   code: "restaurantes",  icon: "restaurantOutline" },
      { name: "Delivery",       code: "delivery",      icon: "fastFoodOutline" },
      { name: "Ocio",           code: "ocio",          icon: "gameControllerOutline" },
      { name: "Ropa",           code: "ropa",          icon: "shirtOutline" },
      { name: "Tecnología",     code: "tecnologia",    icon: "laptopOutline" },
      { name: "Suscripciones",  code: "suscripciones", icon: "refreshOutline" },
      { name: "Cursos",         code: "cursos",        icon: "schoolOutline" },
      { name: "Suplementos",    code: "suplementos",   icon: "fitnessOutline" },
      { name: "Social",         code: "social",        icon: "peopleOutline" }
    ]
  },
  {
    name: "Ingreso", code: "income", category_type: "income",
    color: "#0E96AD", icon: "cashOutline",
    subcategories: [
      { name: "Salario",           code: "salario",          icon: "briefcaseOutline" },
      { name: "Freelance",         code: "freelance",        icon: "codeSlashOutline" },
      { name: "Reembolso",         code: "reembolso",        icon: "returnDownBackOutline" },
      { name: "Arriendo recibido", code: "arriendo_recibido", icon: "businessOutline" },
      { name: "Otros",             code: "otros_ingreso",    icon: "addCircleOutline" }
    ]
  },
  {
    name: "Desconocido", code: "unknown", category_type: "unknown",
    color: "#5B7280", icon: "helpCircleOutline",
    subcategories: []
  }
].freeze

SYSTEM_CATEGORIES.each do |cat_data|
  subcats = cat_data[:subcategories]
  category = Category.find_or_initialize_by(code: cat_data[:code], user_id: nil)
  category.name          = cat_data[:name]
  category.category_type = cat_data[:category_type]
  category.color         = cat_data[:color]
  category.icon          = cat_data[:icon]
  category.is_system     = true
  category.save!

  subcats.each do |sub|
    record = Subcategory.find_or_initialize_by(category: category, code: sub[:code])
    record.name      = sub[:name]
    record.icon      = sub[:icon]
    record.is_system = true
    record.save!
  end
end

puts "Seeded: #{Category.count} categories, #{Subcategory.count} subcategories"

# ─── Auth: roles, permisos, usuarios base ───────────────────────────────────

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

# ─── Agent: service account token ────────────────────────────────────────────

service_token = ENV["DANIEL15K_SERVICE_TOKEN"]
if service_token.present?
  sa = ServiceAccount.find_by(slug: "daniel15k-brain")
  if sa
    sa.store_raw_token!(service_token)
    puts "Seeded: service account token hash updated for #{sa.slug}"
  end
end

# ─── Gamificación: super usuario ─────────────────────────────────────────────
#
# El super usuario (dueño de la cuenta) arranca con bypass_readiness: true y
# nivel 5 para poder testear todos los estados del sistema sin perder datos.

SUPER_USER_EMAIL = "carreraprogrammer@gmail.com".freeze

GAMIFICATION_FEATURES = %w[
  nightly_review
  agent_insights
  recurring
  debts
  planned_expenses
  sinking_funds
  monthly_plan
  liquidity_projection
  propose_budget
  motor_conductual
  chat_dedicado
  simulaciones
].freeze

super_user = User.find_by(email: SUPER_USER_EMAIL)

if super_user
  account = Account.find_by(owner_user: super_user)

  if account
    progress = AccountProgress.find_or_initialize_by(account_id: account.id)
    progress.xp              = 8_000
    progress.level           = 5
    progress.streak_days     = 0
    progress.readiness_score = 100
    progress.avatar_seed     = account.id.to_s
    progress.bypass_readiness = true
    progress.save!

    GAMIFICATION_FEATURES.each do |key|
      flag = FeatureFlag.find_or_initialize_by(account_id: account.id, feature_key: key)
      flag.status      = "active"
      flag.unlocked_at ||= Time.current
      flag.save!
    end

    puts "Seeded: account_progress (level 5, bypass) + #{GAMIFICATION_FEATURES.size} feature_flags for #{SUPER_USER_EMAIL}"
  else
    puts "Skipped gamification seed: no account found for #{SUPER_USER_EMAIL}"
  end
else
  puts "Skipped gamification seed: user #{SUPER_USER_EMAIL} not found"
end
