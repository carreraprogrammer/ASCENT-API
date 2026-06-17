# lib/tasks/accounts.rake
#
# Provisioning manual de cuentas para los primeros usuarios.
# Uso:
#   railway run rails 'accounts:create[Nombre,email@ejemplo.com,password123]'
#   railway run rails accounts:list
#   railway run rails 'accounts:reset_password[email@ejemplo.com,nuevo_password]'

FINANCE_COACH_SCOPES = %w[
  transactions:read transactions:create transactions:update transactions:delete
  debts:read debts:update
  budgets:read budgets:create budgets:update
  recurring_obligations:read recurring_obligations:update
  income_sources:read income_sources:update
  pending_actions:read pending_actions:create pending_actions:update
  summary:read
  financial_context:read financial_context:update
  agent:write
  agent_insights:read agent_insights:write
].freeze

INITIAL_FEATURES_ACTIVE = %w[
  nightly_review
  agent_insights
  recurring
  debts
  planned_expenses
  sinking_funds
  monthly_plan
  liquidity_projection
  chat_dedicado
].freeze

INITIAL_FEATURES_LOCKED = %w[
  propose_budget
  motor_conductual
  simulaciones
].freeze

def accounts_generate_slug(name)
  base = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  slug = base
  i = 2
  while Account.exists?(slug: slug)
    slug = "#{base}-#{i}"
    i += 1
  end
  slug
end

namespace :accounts do
  desc "Crea usuario + account + delegation para el agente finance_coach. Uso: rails 'accounts:create[Nombre,email,password]'"
  task :create, [ :name, :email, :password ] => :environment do |_, args|
    name     = args[:name].to_s.strip
    email    = args[:email].to_s.strip.downcase
    password = args[:password].to_s

    if name.empty? || email.empty? || password.empty?
      abort "Uso: rails 'accounts:create[Nombre,email@ejemplo.com,password123]'"
    end
    abort "ERROR: Password debe tener al menos 8 caracteres." if password.length < 8

    service_account = ServiceAccount.find_by(slug: "daniel15k-brain")
    abort "ERROR: ServiceAccount 'daniel15k-brain' no existe. Corré db:seed primero." unless service_account

    agent_type = AgentType.find_by(slug: "finance_coach")
    abort "ERROR: AgentType 'finance_coach' no existe. Corré db:seed primero." unless agent_type

    abort "ERROR: Ya existe un usuario con el email '#{email}'." if User.exists?(email: email)

    ActiveRecord::Base.transaction do
      # 1. Usuario
      user = User.create!(
        name: name,
        email: email,
        encrypted_password: BCrypt::Password.create(password)
      )
      puts "✓ Usuario creado            id=#{user.id}  email=#{user.email}"

      # 2. Account
      slug    = accounts_generate_slug(name)
      account = Account.create!(owner_user: user, name: name, slug: slug, active: true)
      puts "✓ Account creada            id=#{account.id}  slug=#{account.slug}"

      # 3. AccountProgress (nivel 0 — usuario real, sin bypass)
      AccountProgress.create!(
        account:          account,
        xp:               0,
        level:            0,
        streak_days:      0,
        readiness_score:  0,
        avatar_seed:      account.id.to_s,
        bypass_readiness: false
      )
      puts "✓ AccountProgress creado    level=0"

      # 4. FeatureFlags
      INITIAL_FEATURES_ACTIVE.each do |key|
        FeatureFlag.create!(account: account, feature_key: key, status: "active", unlocked_at: Time.current)
      end
      INITIAL_FEATURES_LOCKED.each do |key|
        FeatureFlag.create!(account: account, feature_key: key, status: "locked")
      end
      puts "✓ FeatureFlags creados      activos=#{INITIAL_FEATURES_ACTIVE.size}  bloqueados=#{INITIAL_FEATURES_LOCKED.size}"

      # 5. Delegation
      Delegation.create!(
        user:            user,
        account:         account,
        service_account: service_account,
        agent_type:      agent_type,
        scopes:          FINANCE_COACH_SCOPES,
        active:          true,
        granted_at:      Time.current
      )
      puts "✓ Delegation creada         scopes=#{FINANCE_COACH_SCOPES.size}"
    end

    puts ""
    puts "═" * 45
    puts "  Cuenta lista"
    puts "  Nombre   : #{name}"
    puts "  Email    : #{email}"
    puts "  Password : #{password}"
    puts "═" * 45
  end

  desc "Lista todas las cuentas con su owner y estado"
  task list: :environment do
    accounts = Account.includes(:owner_user).order(:id)

    if accounts.none?
      puts "No hay cuentas registradas."
      next
    end

    fmt = "%-4s  %-22s  %-32s  %-6s  %s"
    puts format(fmt, "ID", "Nombre", "Email", "Activa", "Creada")
    puts "─" * 78
    accounts.each do |a|
      puts format(
        fmt,
        a.id,
        a.name.truncate(22),
        a.owner_user.email.truncate(32),
        a.active? ? "sí" : "no",
        a.created_at.strftime("%Y-%m-%d")
      )
    end
    puts "─" * 78
    puts "Total: #{accounts.count} cuenta(s)"
  end

  desc "Vincula un Telegram chat_id a una cuenta. Uso: rails 'accounts:set_telegram[email,chat_id]'"
  task :set_telegram, [ :email, :telegram_chat_id ] => :environment do |_, args|
    email           = args[:email].to_s.strip.downcase
    telegram_chat_id = args[:telegram_chat_id].to_s.strip

    if email.empty? || telegram_chat_id.empty?
      abort "Uso: rails 'accounts:set_telegram[email@ejemplo.com,123456789]'"
    end

    user = User.find_by(email: email)
    abort "ERROR: No existe ningún usuario con el email '#{email}'." unless user

    account = Account.find_by(owner_user: user)
    abort "ERROR: No existe ninguna cuenta para el usuario '#{email}'." unless account

    account.update!(telegram_chat_id: telegram_chat_id)
    puts "✓ telegram_chat_id=#{telegram_chat_id} vinculado a la cuenta de #{email}"
  end

  desc "Resetea el password de un usuario. Uso: rails 'accounts:reset_password[email,nuevo_password]'"
  task :reset_password, [ :email, :new_password ] => :environment do |_, args|
    email        = args[:email].to_s.strip.downcase
    new_password = args[:new_password].to_s

    if email.empty? || new_password.empty?
      abort "Uso: rails 'accounts:reset_password[email@ejemplo.com,nuevo_password]'"
    end
    abort "ERROR: Password debe tener al menos 8 caracteres." if new_password.length < 8

    user = User.find_by(email: email)
    abort "ERROR: No existe ningún usuario con el email '#{email}'." unless user

    user.update!(encrypted_password: BCrypt::Password.create(new_password))
    puts "✓ Password actualizado para #{user.email}"
  end

  desc "Resetea el onboarding de una cuenta de PRUEBA: borra sus datos financieros para volver a verlo (no toca usuario/account/delegation). Uso: rails 'accounts:reset_onboarding[email]'"
  task :reset_onboarding, [ :email ] => :environment do |_, args|
    email = args[:email].to_s.strip.downcase
    abort "Uso: rails 'accounts:reset_onboarding[email@ejemplo.com]'" if email.empty?

    protected_emails = %w[carreraprogrammer@gmail.com superadmin@boilerplate.dev].freeze
    if protected_emails.include?(email)
      abort "ERROR: '#{email}' es una cuenta protegida. Usá una cuenta de PRUEBA para probar el onboarding."
    end

    user = User.find_by(email: email)
    abort "ERROR: No existe ningún usuario con el email '#{email}'." unless user

    account = Account.find_by(owner_user: user)
    abort "ERROR: No existe ninguna cuenta para el usuario '#{email}'." unless account

    ActiveRecord::Base.transaction do
      %w[
        Transaction MonthlyFinancialPlan Budget RecurringObligation Debt
        IncomeSource SinkingFund PlannedExpense SavingsGoal FinancialContext
      ].each do |model_name|
        model = model_name.safe_constantize
        next unless model && model.column_names.include?("account_id")

        count = model.where(account_id: account.id).delete_all
        puts "  Borrado: #{count} #{model_name}" if count.positive?
      end
    end

    puts "✓ Onboarding reseteado para #{email}."
    puts "  En el dispositivo, abrí /onboarding/reset (dev/superadmin) para volver a verlo."
  end

  desc "Borra todos los datos de una cuenta (uso: limpieza, smoke tests). Uso: rails 'accounts:delete[email]'"
  task :delete, [ :email ] => :environment do |_, args|
    email = args[:email].to_s.strip.downcase
    abort "Uso: rails 'accounts:delete[email@ejemplo.com]'" if email.empty?

    PROTECTED_EMAILS = %w[carreraprogrammer@gmail.com superadmin@boilerplate.dev].freeze
    if PROTECTED_EMAILS.include?(email)
      abort "ERROR: No se puede borrar la cuenta protegida '#{email}'."
    end

    user = User.find_by(email: email)
    abort "ERROR: No existe ningún usuario con el email '#{email}'." unless user

    account = Account.find_by(owner_user: user)

    ActiveRecord::Base.transaction do
      if account
        # Borrar datos de la cuenta en orden correcto de dependencias
        %w[
          Transaction Delegation FeatureFlag AccountProgress
          MonthlyFinancialPlan Budget RecurringObligation Debt
          IncomeSources SinkingFund PlannedExpense SavingsGoal
          FinancialContext AgentUiEvent PendingAction UserMilestone
          NightAnalysis AgentInsight XpEvent ChatMessage
        ].each do |model_name|
          model = model_name.safe_constantize
          next unless model && model.column_names.include?("account_id")
          count = model.where(account_id: account.id).delete_all
          puts "  Borrado: #{count} #{model_name}" if count > 0
        end
        account.destroy!
        puts "✓ Account borrada: #{account.slug}"
      end

      UserRole.where(user: user).delete_all
      user.destroy!
      puts "✓ Usuario borrado: #{email}"
    end
  end
end
