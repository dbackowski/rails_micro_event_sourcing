# frozen_string_literal: true

module RailsMicroEventSourcing
  module ReadOnly
    extend ActiveSupport::Concern

    def readonly?
      return super if self.class.respond_to?(:enforce_events_only?) && !self.class.enforce_events_only?

      super || !@write_access
    end

    def enable_write_access!
      @write_access = true
    end

    def disable_write_access!
      @write_access = false
    end
  end
end
