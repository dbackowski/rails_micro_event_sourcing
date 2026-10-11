# frozen_string_literal: true

module RailsMicroEventSourcing
  module Eventable
    extend ActiveSupport::Concern
    include ReadOnly

    included do
      class_attribute :enforce_events_only, instance_accessor: false, default: false

      # No `dependent:` on purpose. The log is append-only, so destroying an
      # aggregate must not touch its events: they keep the id they were written
      # with, and the events table can be granted INSERT/SELECT only.
      has_many :events, -> { order(:created_at, :id) }, # rubocop:disable Rails/HasManyOrHasOneDependent
               class_name: 'RailsMicroEventSourcing::Event',
               as: :eventable, inverse_of: :eventable
    end

    class_methods do
      def enforce_events_only!
        self.enforce_events_only = true
      end
    end
  end
end
