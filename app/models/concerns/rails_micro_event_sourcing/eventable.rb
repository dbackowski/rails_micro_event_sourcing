# frozen_string_literal: true

module RailsMicroEventSourcing
  # Include in a model to make it event-sourced: it gains an `events` association
  # and can opt in to event-only writes.
  #
  #   class Customer < ApplicationRecord
  #     include RailsMicroEventSourcing::Eventable
  #     enforce_events_only! # optional
  #   end
  module Eventable
    extend ActiveSupport::Concern
    include ReadOnly

    included do
      has_many :events, class_name: 'RailsMicroEventSourcing::Event',
                        as: :eventable, dependent: :nullify
    end

    class_methods do
      # After this, the model can only be changed by creating an event; direct
      # writes raise ActiveRecord::ReadOnlyRecord. Off by default so the gem drops
      # into an existing app without breaking its writes.
      def enforce_events_only!
        @enforce_events_only = true
      end

      def enforce_events_only?
        @enforce_events_only == true
      end
    end
  end
end
