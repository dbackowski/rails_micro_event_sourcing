# frozen_string_literal: true

module RailsMicroEventSourcing
  # Makes a record writable only while write access is explicitly open.
  #
  # Events include this directly, so they are always frozen after creation.
  # Aggregates get it through the Aggregate concern, but only enforce it once they
  # call `enforce_events_only!` -- until then they behave like normal records.
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
