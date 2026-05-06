Rails.application.config.after_initialize do
  EventBus.subscribe("xp.transaction_confirmed") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "transaction_confirmed",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.transaction_with_subcategory") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "transaction_with_subcategory",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.pending_resolved") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "pending_resolved",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.category_corrected") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "category_corrected",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.plan_confirmed") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "plan_confirmed",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.month_closed_with_snapshot") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "month_closed_with_snapshot",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.debt_registered_complete") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "debt_registered_complete",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.sinking_fund_created") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "sinking_fund_created",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.first_debt_paid_off") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "first_debt_paid_off",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.recurring_income_confirmed") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "recurring_income_confirmed",
      metadata: payload
    )
  end

  EventBus.subscribe("xp.recurring_obligation_confirmed") do |payload|
    Finanzas::Interactors::ComputeXp.new.call(
      account_id: payload[:account_id],
      action_type: "recurring_obligation_confirmed",
      metadata: payload
    )
  end
end
