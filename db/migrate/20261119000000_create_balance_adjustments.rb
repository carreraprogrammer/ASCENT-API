# Ajustes de conciliación del saldo de la cuenta (cuadrar "disponible real" con el banco).
# Viven fuera de transactions para que NO toquen ingresos, gastos, presupuestos, ritmo ni
# ninguna estadística: solo mueven el saldo acumulado (TransactionRepository#confirmed_balance).
# Migra los ajustes que hasta hoy se cargaban como transacciones (metadata.reconciliation o
# conceptos "Ajuste de conciliación…"/"Saldo inicial…") y las borra de transactions.
class CreateBalanceAdjustments < ActiveRecord::Migration[8.0]
  def up
    create_table :balance_adjustments do |t|
      t.references :account, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :amount, null: false # con signo: + suma al saldo, - resta
      t.string :description, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO balance_adjustments (account_id, date, amount, description, metadata, created_at, updated_at)
      SELECT account_id, date::date,
             CASE WHEN transaction_type = 'income' THEN amount ELSE -amount END,
             concept,
             COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('migrated_from_transaction_id', id),
             NOW(), NOW()
      FROM transactions
      WHERE account_id IS NOT NULL
        AND (
          metadata->>'reconciliation' = 'true'
          OR (status = 'confirmed' AND (concept ILIKE 'Ajuste de conciliaci%' OR concept ILIKE 'Saldo inicial%'))
        );
    SQL

    execute <<~SQL
      DELETE FROM transactions
      WHERE id IN (SELECT (metadata->>'migrated_from_transaction_id')::bigint FROM balance_adjustments);
    SQL
  end

  def down
    drop_table :balance_adjustments
  end
end
