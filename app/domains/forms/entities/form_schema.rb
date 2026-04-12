module Forms
  module Entities
    class FormSchema
      VALID_TYPES = %w[text email password number tel url textarea select checkbox radio date datetime-local hidden].freeze
      VALID_METHODS = %w[POST PUT PATCH].freeze
      attr_reader :id, :slug, :title, :submit_label, :submit_endpoint, :submit_method, :fields, :active, :created_at, :updated_at
      def initialize(attrs = {})
        @id = attrs[:id]
        @slug = attrs[:slug]
        @title = attrs[:title]
        @submit_label = attrs[:submit_label]
        @submit_endpoint = attrs[:submit_endpoint]
        @submit_method = attrs[:submit_method]
        @fields = attrs[:fields] || []
        @active = attrs[:active]
        @created_at = attrs[:created_at]
        @updated_at = attrs[:updated_at]
      end
      def active? = @active == true
      def valid? = errors.empty?
      def errors
        errs = []
        errs << "slug is required" if slug.blank?
        errs << "title is required" if title.blank?
        errs << "submit_endpoint is required" if submit_endpoint.blank?
        errs << "submit_method must be POST, PUT, or PATCH" unless VALID_METHODS.include?(submit_method)
        errs << "fields must be an array" unless fields.is_a?(Array)
        errs << "fields cannot be empty" if fields.empty?
        names = []
        fields.each_with_index do |field, i|
          errs << "field[#{i}] name is required" if field["name"].blank?
          errs << "field[#{i}] label is required" if field["label"].blank?
          errs << "field[#{i}] type '#{field['type']}' is not supported" unless VALID_TYPES.include?(field["type"])
          errs << "field[#{i}] order is required" if field["order"].nil?
          errs << "field[#{i}] of type '#{field['type']}' must have options" if %w[select radio].include?(field["type"]) && Array(field["options"]).empty?
          if field["name"].present?
            errs << "field[#{i}] name must be unique" if names.include?(field["name"])
            names << field["name"]
          end
        end
        errs
      end
    end
  end
end
