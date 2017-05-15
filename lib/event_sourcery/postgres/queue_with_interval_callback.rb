module EventSourcery
  module Postgres
    class QueueWithIntervalCallback < ::Queue
      attr_accessor :callback

      def initialize(callback: proc { }, callback_interval: EventSourcery.config.postgres.callback_interval_if_no_new_events, poll_interval: 0.1)
        @callback = callback
        @callback_interval = callback_interval
        @poll_interval = poll_interval
        super()
      end

      def pop(non_block_without_callback = false)
        return super if non_block_without_callback
        pop_with_interval_callback
      end

      private

      def pop_with_interval_callback
        time = Time.now
        loop do
          return pop(true) if !empty?
          if @callback_interval && Time.now > time + @callback_interval
            @callback.call
            time = Time.now
          end
          sleep @poll_interval
        end
      end
    end
  end
end
