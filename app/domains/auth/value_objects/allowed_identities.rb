module Auth
  module ValueObjects
    # TCW-8: el registro está cerrado. ALLOWED_IDENTITIES dice quién entra, separado por comas:
    #   email:<correo verificado>   (Google, y correo y contraseña)
    #   tcw:<sub del cerebro>       (Continuar con The Cyborg Way: el cerebro pone en el token un solo correo,
    #                                que puede ser el noreply de GitHub; el sub es la identidad estable)
    # Una entrada sin prefijo es un correo. Vacía o sin definir: no entra nadie (fail closed).
    # Se revisa antes de buscar o crear un usuario.
    class AllowedIdentities
      def self.from_env(env = ENV)
        new(env.fetch("ALLOWED_IDENTITIES", ""))
      end

      def initialize(raw)
        @emails = Set.new
        @tcw_subs = Set.new
        raw.to_s.split(",").map(&:strip).reject(&:empty?).each do |item|
          kind, value = item.include?(":") ? item.split(":", 2) : [ "email", item ]
          value = value.to_s.strip
          next if value.empty?

          case kind.strip.downcase
          when "email", "google" then @emails << value.downcase
          when "tcw" then @tcw_subs << value
          end
        end
      end

      def allows?(email: nil, tcw_sub: nil)
        (email.present? && @emails.include?(email.to_s.strip.downcase)) ||
          (tcw_sub.present? && @tcw_subs.include?(tcw_sub.to_s))
      end

      def check!(email: nil, tcw_sub: nil)
        raise Auth::Errors::NotAllowed, "Esta cuenta no tiene acceso" unless allows?(email: email, tcw_sub: tcw_sub)
      end
    end
  end
end
