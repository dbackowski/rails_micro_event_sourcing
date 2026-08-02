# frozen_string_literal: true

module RailsMicroEventSourcing
  module Eventable
    extend ActiveSupport::Concern
    include ReadOnly

    included do
      class_attribute :enforce_events_only, instance_accessor: false, default: false

      has_many :events, -> { order(:created_at, :id) },
               class_name: 'RailsMicroEventSourcing::Event',
               as: :eventable, dependent: :nullify, inverse_of: :eventable
    end

    class_methods do
      def enforce_events_only!
        self.enforce_events_only = true
      end
    end
  end
end
