# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # The aggregate is built and has the payload applied during validation, then
  # that same object is saved in before_create. Two things used to slip past
  # that hand-off, both storing an event row that disagrees with the model row
  # and raising nothing:
  #
  # - an aggregate left over from an earlier `valid?` or failed `save` was
  #   reused by `save(validate: false)`, which never re-validates and so never
  #   cleared it — built from old inputs, and read under a lock long released;
  # - a before_save/before_create on the event edited the payload after the
  #   aggregate had already been built from it.
  class EventStaleAggregateTest < ActiveSupport::TestCase
    # Derives the new value from the row's current state, the way a counter or
    # a balance would — so a stale read is a lost update, not just an old value.
    class LastNameAppended < RailsMicroEventSourcing::Event
      aggregate_class Customer

      def apply(aggregate)
        aggregate.last_name = "#{aggregate.last_name}+"
      end
    end

    class NormalizedInBeforeSave < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email

      before_save { self.email = email.strip.downcase }
    end

    class NormalizedInBeforeValidation < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email

      before_validation { self.email = email.strip.downcase }
    end

    def setup
      @customer = Customer::Events::CustomerCreated.create!(
        first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com'
      ).aggregate
    end

    test 'a payload edited after valid? reaches the aggregate when validation is skipped' do
      event = Customer::Events::CustomerUpdated.new(aggregate_id: @customer.id, email: 'first@example.com')
      assert event.valid?

      event.email = 'second@example.com'
      event.save(validate: false)

      assert_equal 'second@example.com', event.payload['email']
      assert_equal 'second@example.com', @customer.reload.email
    end

    test 'a payload fixed after a failed save reaches the aggregate when validation is skipped' do
      event = Customer::Events::CustomerCreated.new(first_name: '', last_name: 'Roe', email: 'roe@example.com')
      assert_not event.save

      event.first_name = 'Unknown'
      event.save(validate: false)

      assert_equal 'Unknown', event.aggregate.reload.first_name
    end

    test 'an aggregate_id changed after valid? targets the new record when validation is skipped' do
      other = Customer::Events::CustomerCreated.create!(
        first_name: 'Other', last_name: 'One', email: 'other@example.com'
      ).aggregate

      event = Customer::Events::CustomerUpdated.new(aggregate_id: @customer.id, first_name: 'Changed')
      assert event.valid?

      event.aggregate_id = other.id
      event.save!(validate: false)

      assert_equal other.id, event.aggregate_id
      assert_equal 'Changed', other.reload.first_name
      assert_equal 'Jane', @customer.reload.first_name
    end

    test 'a row changed by another writer after valid? is re-read, not overwritten from memory' do
      event = LastNameAppended.new(aggregate_id: @customer.id)
      assert event.valid?

      Customer::Events::CustomerUpdated.create!(aggregate_id: @customer.id, last_name: 'Other')
      event.save(validate: false)

      assert_equal 'Other+', @customer.reload.last_name
    end

    test 'editing the payload in before_save raises, pointing at before_validation' do
      error = assert_raises(ArgumentError) do
        NormalizedInBeforeSave.create!(first_name: 'A', last_name: 'B', email: ' A@Example.com ')
      end

      assert_match(/changed its payload or aggregate_id after validation/, error.message)
      assert_match(/before_validation/, error.message)
    end

    test 'nothing is written when the payload is edited in before_save' do
      assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_raises(ArgumentError) do
          NormalizedInBeforeSave.create!(first_name: 'A', last_name: 'B', email: ' A@Example.com ')
        end
      end
    end

    test 'editing the payload in before_validation reaches both the event and the aggregate' do
      event = NormalizedInBeforeValidation.create!(first_name: 'A', last_name: 'B', email: ' A@Example.com ')

      assert_equal 'a@example.com', event.payload['email']
      assert_equal 'a@example.com', event.aggregate.reload.email
    end
  end
end
