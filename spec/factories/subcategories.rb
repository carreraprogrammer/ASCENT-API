FactoryBot.define do
  factory :subcategory do
    category
    name { Faker::Commerce.product_name }
    sequence(:code) { |n| "subcategory_#{n}" }
    is_system { false }

    trait :system do
      is_system { true }
    end

    # RFC-0001: la relación tier↔función vive en el m2m category_subcategories.
    # Reflejamos el vínculo primario también en el join para que los tests ejerciten
    # la misma ruta que producción (backfill + create_with_links).
    after(:create) do |subcategory, _evaluator|
      if subcategory.category_id.present? &&
         !CategorySubcategory.exists?(category_id: subcategory.category_id, subcategory_id: subcategory.id)
        CategorySubcategory.create!(category_id: subcategory.category_id, subcategory_id: subcategory.id)
      end
    end
  end
end
