class CreateFormSchemas < ActiveRecord::Migration[8.0]
  def change
    create_table :form_schemas do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.string :submit_label, null: false, default: 'Submit'
      t.string :submit_endpoint, null: false
      t.string :submit_method, null: false, default: 'POST'
      t.json :fields, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :form_schemas, :slug, unique: true
    add_index :form_schemas, :active
  end
end
