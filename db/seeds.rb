# ─── Finanzas: categorías del sistema ───────────────────────────────────────

SYSTEM_CATEGORIES = [
  {
    name: "Comprometido", code: "committed", category_type: "committed",
    color: "#EF4444", icon: "lock",
    subcategories: [
      { name: "Arriendo",           code: "arriendo" },
      { name: "Créditos",           code: "creditos" },
      { name: "Seguros",            code: "seguros" },
      { name: "Servicios públicos", code: "servicios_publicos" },
      { name: "Colegiaturas",       code: "colegiaturas" }
    ]
  },
  {
    name: "Necesario", code: "necessary", category_type: "necessary",
    color: "#F97316", icon: "shopping-cart",
    subcategories: [
      { name: "Mercado",    code: "mercado" },
      { name: "Gasolina",   code: "gasolina" },
      { name: "Transporte", code: "transporte" },
      { name: "Salud",      code: "salud" },
      { name: "Celular",    code: "celular" }
    ]
  },
  {
    name: "Discrecional", code: "discretionary", category_type: "discretionary",
    color: "#EAB308", icon: "coffee",
    subcategories: [
      { name: "Restaurantes",   code: "restaurantes" },
      { name: "Delivery",       code: "delivery" },
      { name: "Ocio",           code: "ocio" },
      { name: "Ropa",           code: "ropa" },
      { name: "Tecnología",     code: "tecnologia" },
      { name: "Suscripciones",  code: "suscripciones" }
    ]
  },
  {
    name: "Inversión", code: "investment", category_type: "investment",
    color: "#22C55E", icon: "trending-up",
    subcategories: [
      { name: "Cursos",             code: "cursos" },
      { name: "Libros",             code: "libros" },
      { name: "Suplementos",        code: "suplementos" },
      { name: "Herramientas",       code: "herramientas" },
      { name: "Ahorro voluntario",  code: "ahorro_voluntario" }
    ]
  },
  {
    name: "Social", code: "social", category_type: "social",
    color: "#A855F7", icon: "users",
    subcategories: [
      { name: "Regalos",    code: "regalos" },
      { name: "Salidas",    code: "salidas" },
      { name: "Familia",    code: "familia" },
      { name: "Donaciones", code: "donaciones" }
    ]
  },
  {
    name: "Ingreso", code: "income", category_type: "income",
    color: "#06B6D4", icon: "dollar-sign",
    subcategories: [
      { name: "Salario",           code: "salario" },
      { name: "Freelance",         code: "freelance" },
      { name: "Reembolso",         code: "reembolso" },
      { name: "Arriendo recibido", code: "arriendo_recibido" },
      { name: "Otros",             code: "otros_ingreso" }
    ]
  },
  {
    name: "Desconocido", code: "unknown", category_type: "unknown",
    color: "#6B7280", icon: "help-circle",
    subcategories: []
  }
].freeze

SYSTEM_CATEGORIES.each do |cat_data|
  subcats = cat_data[:subcategories]
  category = Category.find_or_create_by!(code: cat_data[:code], user_id: nil) do |c|
    c.name          = cat_data[:name]
    c.category_type = cat_data[:category_type]
    c.color         = cat_data[:color]
    c.icon          = cat_data[:icon]
    c.is_system     = true
  end

  subcats.each do |sub|
    Subcategory.find_or_create_by!(category: category, code: sub[:code]) do |s|
      s.name      = sub[:name]
      s.is_system = true
    end
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

# ─── Finanzas: deudas y gastos fijos de Daniel ──────────────────────────────
# Idempotente — find_or_create_by! en name+user_id

daniel = User.find_by(email: "admin@boilerplate.dev")
unless daniel
  puts "SKIP: usuario admin@boilerplate.dev no encontrado"
  return
end

DEBTS_DATA = [
  {
    name: "CrediExpress #290742",
    debt_type: "personal_loan",
    original_amount: 35_000_000,
    current_balance: 30_378_000,
    monthly_payment: 866_000,
    interest_rate: 1.85,
    status: "active",
    notes: "App Davivienda — débito automático",
  },
  {
    name: "TC LifeMiles #7248",
    debt_type: "credit_card",
    original_amount: 10_000_000,
    current_balance: 7_548_886,
    monthly_payment: 324_000,
    interest_rate: 2.1,
    status: "active",
    notes: "iPhone 17 Pro Max",
  },
  {
    name: "Línea Crédito Plus (moto)",
    debt_type: "personal_loan",
    original_amount: 7_000_000,
    current_balance: 5_353_252,
    monthly_payment: 245_433,
    interest_rate: 1.5,
    status: "active",
    notes: nil,
  },
  {
    name: "Crédito moto",
    debt_type: "personal_loan",
    original_amount: 3_500_000,
    current_balance: 2_786_130,
    monthly_payment: 0,
    interest_rate: 0.0,
    status: "active",
    notes: nil,
  },
  {
    name: "CrediExpress #238105",
    debt_type: "personal_loan",
    original_amount: 4_000_000,
    current_balance: 2_757_501,
    monthly_payment: 83_000,
    interest_rate: 1.85,
    status: "active",
    notes: nil,
  },
  {
    name: "TC Davivienda #1322",
    debt_type: "credit_card",
    original_amount: 500_000,
    current_balance: 79_557,
    monthly_payment: 0,
    interest_rate: 0.0,
    status: "disputed",
    notes: "En disputa legal",
  },
  {
    name: "iPhone papá",
    debt_type: "family",
    original_amount: 2_000_000,
    current_balance: 1_424_000,
    monthly_payment: 178_000,
    interest_rate: 0.0,
    status: "active",
    notes: "Hasta dic-2026",
  },
].freeze

created_debts = {}
DEBTS_DATA.each do |attrs|
  debt = Debt.find_or_create_by!(user: daniel, name: attrs[:name]) do |d|
    d.debt_type       = attrs[:debt_type]
    d.original_amount = attrs[:original_amount]
    d.current_balance = attrs[:current_balance]
    d.monthly_payment = attrs[:monthly_payment]
    d.interest_rate   = attrs[:interest_rate]
    d.status          = attrs[:status]
    d.notes           = attrs[:notes]
  end
  created_debts[attrs[:name]] = debt
  puts "Debt OK: #{debt.name}"
end

RECURRING_OBLIGATIONS_DATA = [
  # Gastos fijos sin deuda asociada
  { name: "Arriendo",          amount: 2_500_000, notes: "Ref 550009900334534", allocatable: nil },
  { name: "YouTube Premium",   amount:    55_000, notes: nil,                   allocatable: nil },
  { name: "Gimnasio (boxeo)",  amount:    50_000, notes: "Temporal en Pasto",   allocatable: nil },
  { name: "Movistar celular",  amount:    40_200, notes: nil,                   allocatable: nil },
  { name: "GitHub",            amount:    37_616, notes: "~$10 USD — TC LifeMiles #7248", allocatable: nil },
  { name: "Amazon Prime",      amount:    24_900, notes: "Evaluar cancelación", allocatable: nil },
  { name: "Railway",           amount:    23_000, notes: nil,                   allocatable: nil },
  # Cuotas vinculadas a deudas
  { name: "CrediExpress #290742 — cuota", amount: 866_000, notes: "App Davivienda auto",  allocatable_name: "CrediExpress #290742" },
  { name: "TC LifeMiles — pago mínimo",   amount: 324_000, notes: "iPhone 17 Pro Max",    allocatable_name: "TC LifeMiles #7248" },
  { name: "Línea Crédito Plus — cuota",   amount: 245_433, notes: "Cascos y matrícula",   allocatable_name: "Línea Crédito Plus (moto)" },
  { name: "CrediExpress #238105 — cuota", amount:  83_000, notes: nil,                    allocatable_name: "CrediExpress #238105" },
  { name: "iPhone papá — cuota",          amount: 178_000, notes: "Hasta dic-2026",       allocatable_name: "iPhone papá" },
].freeze

RECURRING_OBLIGATIONS_DATA.each do |attrs|
  alloc_name = attrs.delete(:allocatable_name)
  alloc      = alloc_name ? created_debts[alloc_name] : attrs.delete(:allocatable)
  rec = RecurringObligation.find_or_create_by!(user: daniel, name: attrs[:name]) do |r|
    r.amount      = attrs[:amount]
    r.notes       = attrs[:notes]
    r.active      = true
    r.allocatable = alloc
  end
  puts "RecurringObligation OK: #{rec.name}"
end

puts "Daniel seed complete — #{Debt.where(user: daniel).count} deudas, #{RecurringObligation.where(user: daniel).count} gastos fijos"
