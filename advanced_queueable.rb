# frozen_string_literal: true

module AdvancedQueueable
  def self.included(base)
    base.extend Wrappers
  end

  module Wrappers
    def perform_async(*args, &)
      raise_nie
      sort_on_precedence(enqueuing_rules).each do |rule|
        if enqueuing_condition_met(rule)
          Rails.logger.debug { "AdvanceQueueable: Performing #{name} after checking enqueuing conditions" }
          super(*args, &)
        else
          Rails.logger.debug { "AdvanceQueueable: #{name} rejected for enqueuing, executing remediation block" }
          if rule[:remediation].is_a?(Proc)
            rule[:remediation].call
          elsif rule[:remediation].is_a?(Array)
            send(rule[:remediation].first, rule[:remediation].second, *args, &)
          else
            return
          end
        end
      end
    end

    def defer(interval, *args, &)
      Rails.logger.debug "Deferring..."
      sleep(interval.seconds)
      perform_async(*args, &)
    end

    def enqueuing_condition_met(rule)
      case rule[:type]
      when :max
        rule[:limit] > rule[:condition].call
      when :min
        Rails.logger.debug { "deferring #{rule[:limit]}" "#{rule[:condition].call}" }
        rule[:limit] < rule[:condition].call
      else
        # <raise exception>
        false
      end
    end

    def sort_on_precedence(rules)
      rules.length > 1 ? rules.sort_by { |rule| rule[:precedence] } : rules
    end

    def raise_nie
      err_msg = "#{name} does not implement .enqueuing_rules but imports AdvancedQueueable"
      raise NotImplementedError, err_msg unless respond_to?(:enqueuing_rules)
    end
  end
end
