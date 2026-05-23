class CreateErrorReports < ActiveRecord::Migration[8.0]
  def change
    create_table :error_reports do |t|
      t.string  :error_hash,       null: false
      t.string  :exception_class,  null: false
      t.text    :message,          null: false
      t.text    :stacktrace,       null: false
      t.string  :endpoint
      t.string  :http_method
      t.jsonb   :params,           default: {}
      t.integer :occurrence_count, null: false, default: 1
      t.string  :status,           null: false, default: "pending"
      t.string  :pr_url
      t.jsonb   :pending_fix
      t.datetime :first_seen_at,   null: false
      t.datetime :last_seen_at,    null: false

      t.timestamps
    end

    add_index :error_reports, :error_hash, unique: true
    add_index :error_reports, :status
  end
end
