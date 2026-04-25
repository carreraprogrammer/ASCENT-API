module Finanzas
  module Interactors
    class AgentPreflight
      def call(account_id:, month:, year:, intent:)
        completeness = detector.call(account_id: account_id, month: month, year: year)
        dimensions = completeness[:dimensions]

        blocking_dimensions = []
        nudges = []
        action = "allow"
        message = nil
        wizard = nil

        case intent.to_s
        when "budgeting"
          blocking_dimensions |= block_if_needed(dimensions, "income_profile", "monthly_plan")
          blocking_dimensions << "recurring_expenses" if dimensions["recurring_expenses"][:status] == "missing"
          nudges << "strategy" if needs_attention?(dimensions["strategy"])
        when "overflow"
          blocking_dimensions |= block_if_needed(dimensions, "income_profile", "monthly_plan")
          nudges << "strategy" if needs_attention?(dimensions["strategy"])
        when "monthly_status"
          nudges << "monthly_plan" if needs_attention?(dimensions["monthly_plan"])
          nudges << "strategy" if needs_attention?(dimensions["strategy"])
        when "debt_status"
          nudges << "debts" if needs_attention?(dimensions["debts"])
          nudges << "strategy" if needs_attention?(dimensions["strategy"])
        else
          nudges << "monthly_plan" if dimensions["monthly_plan"][:status] == "missing"
        end

        if blocking_dimensions.any?
          action = "block"
          wizard = {
            type: "budget_planning",
            reason: "Necesito cerrar tu plan mensual antes de darte una respuesta seria sobre eso."
          }
          message = blocking_message(intent, blocking_dimensions)
        elsif nudges.any?
          action = "soft_nudge"
          message = nudge_message(intent, nudges)
        end

        completeness.merge(
          intent: intent,
          action: action,
          blocking_dimensions: blocking_dimensions.uniq,
          nudge_dimensions: nudges.uniq,
          wizard: wizard,
          message: message
        )
      end

      private

      def block_if_needed(dimensions, *keys)
        keys.select { |key| needs_attention?(dimensions[key]) }
      end

      def needs_attention?(dimension)
        %w[missing partial stale conflicting pending_confirmation].include?(dimension[:status])
      end

      def blocking_message(intent, dimensions)
        case intent.to_s
        when "budgeting"
          "Antes de hablar de presupuesto necesito cerrar tu base del mes: #{humanize_dimensions(dimensions)}."
        when "overflow"
          "Antes de decidir qué hacer con un ingreso extra necesito tu plan mensual al día: #{humanize_dimensions(dimensions)}."
        when "debt_status"
          "Para darte un panorama real de tus deudas necesito: #{humanize_dimensions(dimensions)}."
        else
          "Antes de seguir necesito completar esto: #{humanize_dimensions(dimensions)}."
        end
      end

      def nudge_message(intent, dimensions)
        case intent.to_s
        when "monthly_status"
          "Puedo responderte, pero me falta afinar: #{humanize_dimensions(dimensions)}."
        when "debt_status"
          "Puedo mostrarte las deudas, pero conviene completar: #{humanize_dimensions(dimensions)}."
        else
          "Puedo seguir, pero conviene completar: #{humanize_dimensions(dimensions)}."
        end
      end

      def humanize_dimensions(dimensions)
        labels = {
          "income_profile"     => "perfil de ingresos",
          "debts"              => "deudas",
          "recurring_expenses" => "gastos recurrentes",
          "strategy"           => "estrategia financiera",
          "monthly_plan"       => "plan mensual"
        }
        dimensions.map { |name| labels[name] || name }.join(", ")
      end

      def detector
        @detector ||= DetectCompletenessState.new
      end
    end
  end
end
