# frozen_string_literal: true

module RailsMicroEventSourcing
  class Event < ApplicationRecord
    belongs_to :eventable, polymorphic: true, optional: true
    alias aggregate eventable

    before_validation :reset_aggregate_record, on: :create
    validate :aggregate_must_be_valid, if: :aggregate_class, on: :create
    before_create :capture_metadata
    before_create :apply_to_aggregate, if: :aggregate_class

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
        raise ArgumentError, "#{aggregate.class} must be persisted to be backfilled" unless aggregate.persisted?
        return nil if Event.exists?(eventable: aggregate)

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

    # An aggregate-less event has nothing to resolve an id against, so a value
    # here would be dropped silently. Raise at assignment, where the caller's
    # intent is still visible, and point at what they almost certainly meant.
    def aggregate_id=(value)
      if value.present? && !aggregate_class
        raise ArgumentError,
              "#{self.class} has no aggregate_class, so aggregate_id would be dropped — " \
              'pass eventable: record to link the event without changing it.'
      end

      @aggregate_id = value
    end

    def aggregate_id
      self[:eventable_id] || @aggregate_id
    end

    # The log is append-only: an event is writable while being created and
    # immutable the moment it lands. Deriving that from `persisted?` keeps it
    # true on paths that skip validation, e.g. `save(validate: false)`.
    def readonly?
      super || persisted?
    end

    # The aggregate lives for one save and no longer. One left over from an
    # earlier `valid?` or a failed save was built from the inputs of that
    # moment and read under a lock since released; `save(validate: false)`
    # never re-validates, so nothing else would clear it. Not a callback: none
    # runs before validation on a save that skips validation.
    def save(...) # rubocop:disable Rails/ActiveRecordOverride
      reset_aggregate_record
      super
    end

    def save!(...)
      reset_aggregate_record
      super
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

    def capture_metadata
      self[:metadata] ||= CurrentRequest.metadata.presence
    end

    # Only a missing aggregate is a validation error. The rescue also covers
    # `apply` and the aggregate's own validations, whose failed lookups are
    # bugs: re-raised with their own message, not blamed on aggregate_id.
    def aggregate_must_be_valid
      errors.merge!(aggregate_record.errors) unless aggregate_record.valid?
    rescue ActiveRecord::RecordNotFound
      raise if @aggregate_id.blank? || aggregate_class.exists?(@aggregate_id)

      errors.add(:aggregate_id, 'does not reference an existing record')
    end

    def apply_to_aggregate
      ensure_aggregate_is_eventable!
      ensure_aggregate_inputs_unchanged!
      opened = aggregate_record.tap(&:enable_write_access!)
      # aggregate_must_be_valid already validated this exact object, in this
      # transaction, under this lock — validating again only re-runs the
      # aggregate's validation callbacks, which need not be idempotent.
      opened.save!(validate: false)
      self.eventable = opened
    ensure
      # Closed even when the save raises: the aggregate's after_rollback still
      # runs on this object, after the transaction, and must not write past the
      # guard. Only what was opened — after an earlier raise `opened` is nil.
      opened&.disable_write_access!
    end

    def ensure_aggregate_is_eventable!
      return if aggregate_class.include?(Eventable)

      raise ArgumentError,
            "#{self.class} declares `aggregate_class #{aggregate_class}` but " \
            "#{aggregate_class} does not include RailsMicroEventSourcing::Eventable — " \
            'add the include so the aggregate gets its `events` association and write guard.'
    end

    # The aggregate was built and validated from the payload as it stood during
    # validation. A before_save/before_create on the event that edits it
    # afterwards would store one value in the log and another on the record.
    # Rebuilding here instead would save an aggregate that never ran its own
    # validations or before_validation callbacks, so fail and say where to move it.
    def ensure_aggregate_inputs_unchanged!
      return if @aggregate_record.nil? || @aggregate_inputs == aggregate_inputs

      raise ArgumentError,
            "#{self.class} changed its payload or aggregate_id after validation, so the " \
            "#{aggregate_class} was validated with different values than the event stores — " \
            'make the change in before_validation instead of before_save/before_create.'
    end

    def reset_aggregate_record
      @aggregate_record = nil
    end

    def aggregate_record
      @aggregate_record ||= begin
        @aggregate_inputs = aggregate_inputs
        find_or_build_aggregate.tap { |record| apply(record) }
      end
    end

    def aggregate_inputs
      [@aggregate_id, self[:payload].deep_dup]
    end

    # The lookup reads only aggregate_id, and apply_to_aggregate overwrites
    # eventable afterwards — so an eventable set by the caller (eventable:,
    # or building through `events`) would be silently replaced by a freshly
    # built record. Every such path sets eventable_type before save; the
    # documented aggregate_id path never does.
    def find_or_build_aggregate
      if self[:eventable_type].present?
        raise ArgumentError,
              "#{self.class} finds its #{aggregate_class} by aggregate_id: — " \
              'eventable: and building through `events` are for aggregate-less events.'
      end

      return aggregate_class.new if @aggregate_id.blank?

      aggregate_class.lock.find(@aggregate_id)
    end
  end
end
