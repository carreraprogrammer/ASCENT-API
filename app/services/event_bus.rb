class EventBus
  @subscribers = Hash.new { |h, k| h[k] = [] }

  class << self
    def subscribe(event_key, &block)
      @subscribers[event_key.to_s] << block
    end

    def publish(event, payload = {})
      key = event_key_for(event)
      return true if key.nil?

      @subscribers[key].each do |handler|
        handler.call(payload)
      rescue StandardError => e
        Rails.logger.error("[EventBus] Handler error for #{key}: #{e.message}")
      end

      true
    end

    private

    def event_key_for(event)
      case event
      when String, Symbol
        event.to_s
      else
        event.class.name&.gsub("::", ".")&.downcase
      end
    end
  end
end
