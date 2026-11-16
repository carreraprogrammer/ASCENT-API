namespace :ascent do
  # ASC-4 fase 0. bin/rails "ascent:reset_stage[correo]" (por defecto OWNER_EMAIL). Imprime solo conteos.
  desc "Reinicia Tu ascenso en el Fondo semilla: ajusta a 0 las metas de emergencia (idempotente por día)"
  task :reset_stage, [ :email ] => :environment do |_task, args|
    email = args[:email].presence || ENV.fetch("OWNER_EMAIL")
    user = ::User.find_by!(email: email)
    account = user.default_account
    result = Finanzas::Interactors::ResetAscentStage.new.call(account_id: account.id, user_id: user.id)
    puts "goals=#{result[:goals]} adjusted=#{result[:adjusted]} already_done=#{result[:already_done]} " \
         "already_zero=#{result[:already_zero]}"
  end
end
