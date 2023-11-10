# frozen_string_literal: true

module Test
  module Increments
    class FiveS
      include Sidekiq::Job
      include AdvancedQueueable

      sidekiq_options queue: "default", retry: 0

      def perform
        sleep(5.seconds)
        Rails.logger.debug "done"
      end

      def self.enqueuing_rules
        [
          {
            type: :max,
            limit: 2,
            condition: -> { Sidekiq::Queue.new.size }
          }
        ]
      end
    end
  end
end
