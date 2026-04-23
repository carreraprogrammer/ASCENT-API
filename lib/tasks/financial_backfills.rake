namespace :financial_backfills do
  desc "Backfill recurring obligation source references for high-confidence debt matches"
  task link_recurring_obligation_sources: :environment do
    result = Finanzas::Interactors::BackfillRecurringObligationSources.new.call

    puts "linked=#{result.linked.size}"
    result.linked.each do |row|
      puts "  linked recurring_obligation=#{row[:recurring_obligation_id]} debt=#{row[:debt_id]} name=#{row[:recurring_obligation_name]}"
    end

    puts "already_linked=#{result.already_linked.size}"
    result.already_linked.each do |row|
      puts "  already linked recurring_obligation=#{row[:recurring_obligation_id]} name=#{row[:recurring_obligation_name]}"
    end

    puts "ambiguous=#{result.ambiguous.size}"
    result.ambiguous.each do |row|
      puts "  ambiguous recurring_obligation=#{row[:recurring_obligation_id]} candidates=#{row[:candidate_debt_ids].join(',')}"
    end

    puts "skipped=#{result.skipped.size}"
    result.skipped.each do |row|
      puts "  skipped recurring_obligation=#{row[:recurring_obligation_id]} reason=#{row[:reason]}"
    end
  end
end
