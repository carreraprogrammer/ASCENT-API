class RenameDiscretionaryCategoryToFlexible < ActiveRecord::Migration[8.0]
  def up
    Category.where(code: "discretionary").update_all(name: "Flexible")

    execute <<~SQL
      UPDATE monthly_financial_plans
      SET execution_snapshot = jsonb_set(
        execution_snapshot,
        '{categories}',
        (
          SELECT jsonb_agg(
            CASE
              WHEN category->>'code' = 'discretionary'
              THEN jsonb_set(category, '{name}', '"Flexible"'::jsonb)
              ELSE category
            END
          )
          FROM jsonb_array_elements(COALESCE(execution_snapshot->'categories', '[]'::jsonb)) AS category
        )
      )
      WHERE execution_snapshot ? 'categories';
    SQL
  end

  def down
    Category.where(code: "discretionary").update_all(name: "Discrecional")

    execute <<~SQL
      UPDATE monthly_financial_plans
      SET execution_snapshot = jsonb_set(
        execution_snapshot,
        '{categories}',
        (
          SELECT jsonb_agg(
            CASE
              WHEN category->>'code' = 'discretionary'
              THEN jsonb_set(category, '{name}', '"Discrecional"'::jsonb)
              ELSE category
            END
          )
          FROM jsonb_array_elements(COALESCE(execution_snapshot->'categories', '[]'::jsonb)) AS category
        )
      )
      WHERE execution_snapshot ? 'categories';
    SQL
  end
end