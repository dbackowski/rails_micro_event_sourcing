# frozen_string_literal: true

module RailsMicroEventSourcing
  class Event < ApplicationRecord
    include ReadOnly

    belongs_to :eventable, polymorphic: true, optional: true
    alias aggregate eventable

    before_validation :open_for_writing, on: :create
    before_validation :reset_aggregate_record, on: :create
    validate :aggregate_must_be_valid, if: :aggregate_class, on: :create
    before_create :capture_metadata
    before_create :apply_to_aggregate, if: :aggregate_class
    after_create :disable_write_access!

    class << self
      def aggregate_class(klass = nil)
        return @aggregate_class = klass if klass
        return @aggregate_class if defined?(@aggregate_class) && @aggregate_class

        superclass.respond_to?(:aggregate_class) ? superclass.aggregate_class : nil
      end

      def event_attributes(*names)
        names.each do |name|
          key = name.to_s
          define_method(name) { (self[:payload] || {})[key] }
          define_method("#{name}=") { |value| self[:payload] = (self[:payload] || {}).merge(key => value) }
        end
        own_event_attribute_names.concat(names.map(&:to_s))
      end

      def event_attribute_names
        inherited = superclass.respond_to?(:event_attribute_names) ? superclass.event_attribute_names : []
        (inherited + own_event_attribute_names).uniq
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

      private

      def own_event_attribute_names
        @own_event_attribute_names ||= []
      end
    end

    attr_writer :aggregate_id

    def aggregate_id
      self[:eventable_id] || (@aggregate_id if aggregate_class)
    end

    def apply(aggregate)
      self.class.event_attribute_names.each do |key|
        next unless self[:payload]&.key?(key)

        unless aggregate.respond_to?("#{key}=")
          raise ArgumentError,
                "#{self.class} declares `event_attributes :#{key}` but its aggregate " \
                "#{aggregate.class} has no ##{key}= setter — check the attribute name " \
                'matches a column.'
        end

        aggregate.public_send("#{key}=", self[:payload][key])
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
      self[:metadata] ||= CurrentRequest.metadata.presence
    end

    def aggregate_must_be_valid
      errors.merge!(aggregate_record.errors) unless aggregate_record.valid?
    rescue ActiveRecord::RecordNotFound
      errors.add(:aggregate_id, 'does not reference an existing record')
    end

    def apply_to_aggregate
      ensure_aggregate_is_eventable!
      aggregate_record.enable_write_access!
      aggregate_record.save!
      aggregate_record.disable_write_access!
      self.eventable = aggregate_record
    end

    def ensure_aggregate_is_eventable!
      return if aggregate_class.include?(Eventable)

      raise ArgumentError,
            "#{self.class} declares `aggregate_class #{aggregate_class}` but " \
            "#{aggregate_class} does not include RailsMicroEventSourcing::Eventable — " \
            'add the include so the aggregate gets its `events` association and write guard.'
    end

    def reset_aggregate_record
      @aggregate_record = nil
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
