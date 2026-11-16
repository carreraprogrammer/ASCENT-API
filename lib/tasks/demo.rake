namespace :demo do
  # ASC-4 fase 6. bin/rails demo:seed crea o restablece la cuenta demo (DEMO_EMAIL, por defecto
  # demo@ascent.thecyborgway.dev) con datos ficticios. Idempotente. Imprime solo conteos.
  desc "Crea o restablece la cuenta demo con datos ficticios (idempotente)"
  task seed: :environment do
    result = Demo::Interactors::ResetDemoAccount.new.call
    puts "demo account_id=#{result[:account_id]} transactions=#{result[:transactions]} debts=#{result[:debts]} " \
         "recurring_obligations=#{result[:recurring_obligations]} savings_goals=#{result[:savings_goals]}"
  end
end
