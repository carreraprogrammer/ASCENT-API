module Finanzas
  module Entities
    class Category
      attr_reader :id, :user_id, :name, :code, :category_type,
                  :color, :icon, :is_system, :created_at, :updated_at,
                  :subcategories

      def initialize(attrs = {})
        @id            = attrs[:id]
        @user_id       = attrs[:user_id]
        @name          = attrs[:name]
        @code          = attrs[:code]
        @category_type = attrs[:category_type]
        @color         = attrs[:color]
        @icon          = attrs[:icon]
        @is_system     = attrs[:is_system] || false
        @created_at    = attrs[:created_at]
        @updated_at    = attrs[:updated_at]
        @subcategories = attrs[:subcategories] || []
      end

      def system? = @is_system == true
    end
  end
end
