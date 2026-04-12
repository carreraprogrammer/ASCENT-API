module Forms
  module Repositories
    class FormSchemaRepository
      def all_active
        ::FormSchema.where(active: true).order(:slug).map { |r| map_to_entity(r) }
      end
      def find_by_slug(slug)
        record = ::FormSchema.find_by(slug: slug, active: true)
        record && map_to_entity(record)
      end
      def create(attrs)
        record = ::FormSchema.create!(slug: attrs[:slug], title: attrs[:title], submit_label: attrs[:submit_label] || "Submit", submit_endpoint: attrs[:submit_endpoint], submit_method: attrs[:submit_method] || "POST", fields: serialize_fields(attrs[:fields]), active: attrs.fetch(:active, true))
        map_to_entity(record)
      end
      def update(slug, attrs)
        record = ::FormSchema.find_by!(slug: slug)
        update_attrs = attrs.slice(:title, :submit_label, :submit_endpoint, :submit_method, :active)
        update_attrs[:fields] = serialize_fields(attrs[:fields]) if attrs.key?(:fields)
        record.update!(update_attrs)
        map_to_entity(record)
      end
      def deactivate(slug)
        ::FormSchema.find_by!(slug: slug).update!(active: false)
      end
      private
      def serialize_fields(fields)
        fields.is_a?(String) ? fields : JSON.generate(fields)
      end

      def deserialize_fields(fields)
        fields.is_a?(String) ? JSON.parse(fields) : fields
      end

      def map_to_entity(record)
        Forms::Entities::FormSchema.new(id: record.id, slug: record.slug, title: record.title, submit_label: record.submit_label, submit_endpoint: record.submit_endpoint, submit_method: record.submit_method, fields: deserialize_fields(record.fields), active: record.active, created_at: record.created_at, updated_at: record.updated_at)
      end
    end
  end
end
