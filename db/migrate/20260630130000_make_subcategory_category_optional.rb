class MakeSubcategoryCategoryOptional < ActiveRecord::Migration[8.0]
  # RFC-0001 — desacople función↔tier. La subcategoría es una FUNCIÓN ("salud",
  # "restaurantes") ortogonal al tier de agencia (que vive en la categoría de la
  # transacción). Dejar de forzar que una subcategoría pertenezca a UNA sola categoría:
  # `category_id` pasa a nullable. (Expand; no borra nada, no nulea nada aún — el dedupe
  # y el nil van coordinados con el fix del web, ver plan D2/D3.)
  def change
    change_column_null :subcategories, :category_id, true
  end
end
