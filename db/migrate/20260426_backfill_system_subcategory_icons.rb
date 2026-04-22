class BackfillSystemSubcategoryIcons < ActiveRecord::Migration[8.0]
  ICON_MAP = {
    "arriendo"           => "homeOutline",
    "creditos"           => "cardOutline",
    "seguros"            => "shieldOutline",
    "servicios_publicos" => "flashOutline",
    "colegiaturas"       => "schoolOutline",
    "mercado"            => "cartOutline",
    "gasolina"           => "carOutline",
    "transporte"         => "busOutline",
    "salud"              => "heartOutline",
    "celular"            => "phonePortraitOutline",
    "restaurantes"       => "restaurantOutline",
    "delivery"           => "fastFoodOutline",
    "ocio"               => "gameControllerOutline",
    "ropa"               => "shirtOutline",
    "tecnologia"         => "laptopOutline",
    "suscripciones"      => "refreshOutline",
    "cursos"             => "schoolOutline",
    "libros"             => "bookOutline",
    "suplementos"        => "fitnessOutline",
    "herramientas"       => "constructOutline",
    "ahorro_voluntario"  => "saveOutline",
    "regalos"            => "giftOutline",
    "salidas"            => "peopleOutline",
    "familia"            => "heartOutline",
    "donaciones"         => "handLeftOutline",
    "salario"            => "briefcaseOutline",
    "freelance"          => "codeSlashOutline",
    "reembolso"          => "returnDownBackOutline",
    "arriendo_recibido"  => "businessOutline",
    "otros_ingreso"      => "addCircleOutline"
  }.freeze

  def up
    ICON_MAP.each do |code, icon|
      Subcategory.where(code: code, is_system: true, icon: [nil, ""]).update_all(icon: icon)
    end
  end

  def down
    # Intentionally irreversible — nullifying icons degrades UX with no benefit.
  end
end
