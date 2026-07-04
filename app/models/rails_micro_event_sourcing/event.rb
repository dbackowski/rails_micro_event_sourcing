# frozen_string_literal: true

module RailsMicroEventSourcing
  class Event < ApplicationRecord
    include ReadOnly

    belongs_to :eventable, polymorphic: true, optional: true
    alias aggregate eventable

    before_validation :open_for_writing, on: :create
    validate :aggregate_must_be_valid, if: :aggregate_class, on: :create
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

    def aggregate_must_be_valid
      record = build_and_apply
      errors.merge!(record.errors) unless record.valid?
    end

    def apply_to_aggregate
      record = build_and_apply(lock: true)
      record.enable_write_access!
      record.save!
      record.disable_write_access!
      self.eventable = record
    end

    def build_and_apply(lock: false)
      find_or_build_aggregate(lock:).tap { |record| apply(record) }
    end

    def find_or_build_aggregate(lock: false)
      return aggregate_class.new if @aggregate_id.blank?

      scope = lock ? aggregate_class.lock : aggregate_class
      scope.find(@aggregate_id)
    end
  end
end
