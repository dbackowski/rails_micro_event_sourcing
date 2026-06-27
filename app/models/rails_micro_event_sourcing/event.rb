# frozen_string_literal: true

module RailsMicroEventSourcing
  class Event < ApplicationRecord
    include ReadOnly

    belongs_to :eventable, polymorphic: true, optional: true
    alias aggregate eventable

    before_validation :open_for_writing, on: :create
    before_create :capture_metadata
    before_create :apply_to_aggregate, if: :aggregate_class
    after_create :disable_write_access!

    class << self
      def aggregate_class(klass = nil)
        klass ? @aggregate_class = klass : @aggregate_class
      end

      def event_attributes(*names)
        names.each do |name|
          key = name.to_s
          define_method(name) { (payload || {})[key] }
          define_method("#{name}=") { |value| self.payload = (payload || {}).merge(key => value) }
        end
      end
    end

    attr_writer :aggregate_id

    def aggregate_id
      eventable_id || @aggregate_id
    end

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
