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
        event_attribute_names.concat(names.map(&:to_s))
      end

      def event_attribute_names
        @event_attribute_names ||= []
      end

      def backfill!(aggregate, payload: nil, created_at: nil, metadata: nil)
        raise ArgumentError, "#{name} has no aggregate_class" unless aggregate_class
        return nil if exists?(eventable: aggregate)

        insert!( # rubocop:disable Rails/SkipsModelValidations
          {
            type: name,
            eventable_type: aggregate.class.polymorphic_name,
            eventable_id: aggregate.id,
            payload: payload || aggregate.attributes,
            metadata: metadata,
            created_at: created_at || aggregate.created_at || Time.current
          },
          returning: false
        )
      end
    end

    attr_writer :aggregate_id

    def aggregate_id
      eventable_id || @aggregate_id
    end

    def apply(aggregate)
      self.class.event_attribute_names.each do |key|
        next unless payload&.key?(key)

        unless aggregate.respond_to?("#{key}=")
          raise ArgumentError,
                "#{self.class} declares `event_attributes :#{key}` but its aggregate " \
                "#{aggregate.class} has no ##{key}= setter — check the attribute name " \
                'matches a column.'
        end

        aggregate.public_send("#{key}=", payload[key])
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
      errors.merge!(aggregate_record.errors) unless aggregate_record.valid?
    rescue ActiveRecord::RecordNotFound
      errors.add(:aggregate_id, 'does not reference an existing record')
    end

    def apply_to_aggregate
      aggregate_record.enable_write_access!
      aggregate_record.save!
      aggregate_record.disable_write_access!
      self.eventable = aggregate_record
    end

    def aggregate_record
      @aggregate_record ||= find_or_build_aggregate.tap { |record| apply(record) }
    end

    def find_or_build_aggregate
      return aggregate_class.new if @aggregate_id.blank?

      aggregate_class.lock.find(@aggregate_id)
    end
  end
end
