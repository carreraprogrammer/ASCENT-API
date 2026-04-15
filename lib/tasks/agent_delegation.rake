namespace :agent_delegation do
  desc "Lista las accounts existentes con owner y slug"
  task list_accounts: :environment do
    puts "id\towner_user_id\tslug\tname"
    Account.order(:id).find_each do |account|
      puts "#{account.id}\t#{account.owner_user_id}\t#{account.slug}\t#{account.name}"
    end
  end

  desc "Guarda el token hash de un service account desde env"
  task store_service_token: :environment do
    slug = ENV.fetch("SERVICE_ACCOUNT_SLUG")
    raw_token = ENV.fetch("SERVICE_ACCOUNT_TOKEN")

    service_account = ServiceAccount.find_by!(slug: slug)
    service_account.store_raw_token!(raw_token)

    puts "token hash actualizado para #{service_account.slug}"
  end
end
