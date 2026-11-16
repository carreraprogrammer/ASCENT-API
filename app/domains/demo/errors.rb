module Demo
  module Errors
    # La cuenta demo todavía no existe (falta correr bin/rails demo:seed).
    class NotSeeded < StandardError; end
    # Solo el superadministrador puede cambiar su sesión a la cuenta demo.
    class Forbidden < StandardError; end
    # DEMO_EMAIL ya pertenece a un usuario real: nunca se reutiliza ni se modifica.
    class EmailTaken < StandardError; end
  end
end
