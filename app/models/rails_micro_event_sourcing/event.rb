# frozen_string_literal: true

module RailsMicroEventSourcing
  # Base class for all events. Subclass it, declare which model it changes with
  # `aggregate_class`, and which payload fields it carries with `event_attributes`.
  #
  # Creating an event runs the subclass's own validations, applies the payload to
  # the aggregate, and saves both the aggregate and the (immutable) event row in a
  # single transaction. The aggregate row is the current state -- events are never
  # replayed.
  class Event < ApplicationRecord
    include ReadOnly

    belongs_to :eventable, polymorphic: true, optional: true
    alias aggregate eventable

    before_validation :open_for_writing, on: :create
    before_create :capture_metadata
    before_create :apply_to_aggregate, if: :aggregate_class
    after_create :disable_write_access!

    class << self
      # Declares which model this event creates/updates. Omit it for audit-only
      # events that don't touch any model.
      def aggregate_class(klass = nil)
        klass ? @aggregate_class = klass : @aggregate_class
      end

      # Declares the payload fields, backed by the JSON `payload` column.
      def event_attributes(*names)
        names.each do |name|
          key = name.to_s
          define_method(name) { (payload || {})[key] }
          define_method("#{name}=") { |value| self.payload = (payload || {}).merge(key => value) }
        end
      end
    end

    # `aggregate_id` is not a column. As input it names the existing aggregate to
    # load; as output it mirrors the persisted polymorphic id.
    attr_writer :aggregate_id

    def aggregate_id
      eventable_id || @aggregate_id
    end

    # Copies every payload field onto the aggregate. Override in a subclass for
    # computed values or custom transformations.
    def apply(aggregate)
      (payload || {}).each do |key, value|
        aggregate.public_send("#{key}=", value) if aggregate.respond_to?("#{key}=")
      end
    end

    private

    def aggregate_class
      self.class.aggregate_class
    end

    def open_for_writing
      enable_write_access!
    end

    def capture_metadata
      self.metadata ||= CurrentRequest.metadata.presence
    end

    def apply_to_aggregate
      record = find_or_build_aggregate
      record.enable_write_access!
      apply(record)
      record.save!
      record.disable_write_access!
      self.eventable = record
    end

    def find_or_build_aggregate
      @aggregate_id.present? ? aggregate_class.lock.find(@aggregate_id) : aggregate_class.new
    end
  end
end
