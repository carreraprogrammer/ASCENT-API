class AddAgentWriteScopeToDelegations < ActiveRecord::Migration[8.0]
  def up
    new_scopes = %w[agent:write agent_insights:write agent_insights:read]
    Delegation.find_each do |d|
      updated = (Array(d.scopes) | new_scopes)
      d.update_columns(scopes: updated)
    end
  end

  def down
    remove_scopes = %w[agent:write agent_insights:write agent_insights:read]
    Delegation.find_each do |d|
      updated = Array(d.scopes) - remove_scopes
      d.update_columns(scopes: updated)
    end
  end
end
