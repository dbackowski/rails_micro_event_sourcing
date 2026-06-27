# frozen_string_literal: true

module RailsMicroEventSourcing
  module Eventable
    extend ActiveSupport::Concern
    include ReadOnly

    included do
      has_many :events, -> { order(:created_at, :id) },
               class_name: 'RailsMicroEventSourcing::Event',
               as: :eventable, dependent: :nullify
    end

    class_methods do
      def enforce_events_only!
        @enforce_events_only = true
      end

      def enforce_events_only?
        @enforce_events_only == true
      end
    end
  end
end
