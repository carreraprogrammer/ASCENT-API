class AddTagsToTransactions < ActiveRecord::Migration[8.0]
  # RFC-0001 — eje ortogonal de tags. Cuando `social` deja de ser categoría de agencia,
  # su semántica relacional se conserva como tag (`social`). Extensible a futuro
  # (ej. `time_saving`, recomendado por el research brief). Aditivo; default [] = sin tags.
  def change
    add_column :transactions, :tags, :jsonb, default: [], null: false
    add_index :transactions, :tags, using: :gin
  end
end
