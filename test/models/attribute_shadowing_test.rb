# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # `event_attributes` defines methods on the event class, so a declared name that
  # matches one of the events table's own columns shadows that column's accessor.
  # The declaration is allowed to win for readers — that is what the caller asked
  # for — but the gem's own internals must not route through it, or they silently
  # read and write the wrong place. These cover the columns the write path touches.
  class AttributeShadowingTest < ActiveSupport::TestCase
    teardown { CurrentRequest.reset }

    # An aggregate-less audit event carrying its own `metadata` field. Nothing in
    # the apply path runs for these, so the column accessors are the only guard.
    class LoginFailed < RailsMicroEventSourcing::Event
      event_attributes :email, :metadata
    end

    test 'request metadata reaches the column even when metadata is a declared attribute' do
      CurrentRequest.metadata = { request_id: 'abc-123' }

      event = LoginFailed.create!(email: 'jane@example.com').reload

      assert_equal({ 'request_id' => 'abc-123' }, event.read_attribute(:metadata))
    end

    test 'a declared metadata payload key and the metadata column coexist' do
      CurrentRequest.metadata = { request_id: 'abc-123' }

      event = LoginFailed.create!(email: 'jane@example.com', metadata: { attempt: 2 }).reload

      assert_equal({ 'request_id' => 'abc-123' }, event.read_attribute(:metadata))
      assert_equal({ 'attempt' => 2 }, event.metadata)
      assert_equal({ 'attempt' => 2 }, event.payload['metadata'])
    end

    # The generated accessors read the payload column. If they did so by calling
    # `payload`, declaring that name would make the getter call itself.
    class PayloadNamed < RailsMicroEventSourcing::Event
      event_attributes :payload
    end

    test 'declaring payload does not make its reader recurse' do
      assert_nil PayloadNamed.new.payload

      event = PayloadNamed.create!(payload: 'nested').reload

      assert_equal 'nested', event.payload
      assert_equal({ 'payload' => 'nested' }, event.read_attribute(:payload))
    end

    # aggregate_id reports the linked record by reading the eventable_id column.
    class CustomerCreatedNamingEventableId < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email, :eventable_id
    end

    test 'aggregate_id reports the real record when eventable_id is a declared attribute' do
      event = CustomerCreatedNamingEventableId.create!(
        first_name: 'Jane', last_name: 'Roe', email: 'jane@example.com'
      )

      assert_equal event.aggregate.id, event.aggregate_id
    end
  end
end
