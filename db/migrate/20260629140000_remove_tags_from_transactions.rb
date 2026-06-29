class RemoveTagsFromTransactions < ActiveRecord::Migration[8.0]
  # Revierte el tag `social` (20260629130000). Decisión de diseño: la semántica social
  # ya la dan las subcategorías (Regalos, Salidas, Familia, Donaciones, Amigos); un eje
  # de tags era un eje paralelo innecesario. Social se conserva como subcategoría bajo su
  # tier de agencia. La columna estaba sin uso (default []), así que el drop es seguro.
  def change
    remove_column :transactions, :tags, :jsonb, default: [], null: false
  end
end
