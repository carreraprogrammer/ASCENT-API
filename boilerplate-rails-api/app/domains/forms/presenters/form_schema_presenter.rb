module Forms
  module Presenters
    class FormSchemaPresenter
      def self.single(schema)
        { data: serialize(schema) }
      end
      def self.collection(schemas)
        { data: schemas.map { |s| serialize(s) }, meta: { total: schemas.size } }
      end
      private_class_method def self.serialize(schema)
        { id: schema.slug, type: "form_schemas", attributes: { slug: schema.slug, title: schema.title, submit_label: schema.submit_label, submit_endpoint: schema.submit_endpoint, submit_method: schema.submit_method, fields: schema.fields.sort_by { |f| f["order"].to_i } } }
      end
    end
  end
end
