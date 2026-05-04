class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :date, null: false          # DD/MM — hora Colombia
      t.string :concept, null: false
      t.string :product                    # nequi | tc1234 | tc5678 | debito | bre-b
      t.integer :amount, null: false       # en pesos, siempre positivo
      t.string :transaction_type, null: false, default: "expense"  # expense | income
      t.references :category, null: true, foreign_key: true
      t.references :subcategory, null: true, foreign_key: true
      t.string :source, default: "manual"  # telegram | gmail | manual
      t.string :status, null: false, default: "confirmed"  # confirmed | pending | projected
      t.datetime :clarification_requested_at
      t.datetime :clarification_resolved_at
      t.jsonb :metadata, default: {}
      t.integer :year, null: false
      t.integer :month, null: false
      t.timestamps
    end

    add_index :transactions, [ :user_id, :year, :month ]
    add_index :transactions, [ :user_id, :status ]
  end
end
