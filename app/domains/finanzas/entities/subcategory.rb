module Finanzas
  module Entities
    class Subcategory
      attr_reader :id, :category_id, :user_id, :name, :code, :icon, :is_system,
                  :created_at, :updated_at

      def initialize(attrs = {})
        @id          = attrs[:id]
        @category_id = attrs[:category_id]
        @user_id     = attrs[:user_id]
        @name        = attrs[:name]
        @code        = attrs[:code]
        @icon        = attrs[:icon]
        @is_system   = attrs[:is_system] || false
        @created_at  = attrs[:created_at]
        @updated_at  = attrs[:updated_at]
      end

      def system? = @is_system == true
    end
  end
end
