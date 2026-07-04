# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  class EventTest < ActiveSupport::TestCase
    teardown { CurrentRequest.reset }

    test 'a create event materializes the aggregate' do
      event = Customer::Events::CustomerCreated.create!(first_name: 'John', last_name: 'Doe', email: 'john@example.com')

      customer = event.aggregate
      assert_instance_of Customer, customer
      assert customer.persisted?
      assert_equal 'John', customer.first_name
      assert_equal 'Doe', customer.last_name
      assert_equal 'john@example.com', customer.email
    end

    test 'the event is linked to the aggregate' do
      event = create_customer_event

      assert_equal event.aggregate.id, event.aggregate_id
      assert_equal [event], event.aggregate.events.to_a
    end

    test 'the payload is stored on the event' do
      event = create_customer_event

      assert_equal({ 'first_name' => 'John', 'last_name' => 'Doe', 'email' => 'john@example.com' }, event.payload)
    end

    test 'request metadata is captured when present' do
      CurrentRequest.metadata = { request_id: 'abc-123' }

      assert_equal({ 'request_id' => 'abc-123' }, create_customer_event.reload.metadata)
    end

    test 'metadata is nil when no request context is set' do
      assert_nil create_customer_event.metadata
    end

    test 'an update event modifies the existing aggregate' do
      created = create_customer_event

      Customer::Events::CustomerUpdated.create!(aggregate_id: created.aggregate_id, email: 'new@example.com')

      customer = Customer.find(created.aggregate_id)
      assert_equal 'new@example.com', customer.email
    end

    test 'an update only changes the attributes in its payload' do
      created = create_customer_event

      Customer::Events::CustomerUpdated.create!(aggregate_id: created.aggregate_id, email: 'new@example.com')

      customer = Customer.find(created.aggregate_id)
      assert_equal 'John', customer.first_name
      assert_equal 'Doe', customer.last_name
    end

    test 'events are immutable after creation' do
      event = create_customer_event

      assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(metadata: { tampered: true }) }
    end

    test 'an invalid event is not saved and does not create an aggregate' do
      assert_no_difference ['Account.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_raises(ActiveRecord::RecordInvalid) { Account::Events::AccountCreated.create!(name: nil) }
      end
    end

    test 'aggregate validation errors are surfaced on the event' do
      create_customer_event(email: 'taken@example.com')

      event = Customer::Events::CustomerCreated.new(
        first_name: 'Jane', last_name: 'Roe', email: 'taken@example.com'
      )

      assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_not event.save
      end
      assert_not event.persisted?
      assert_includes event.errors[:email], 'has already been taken'
    end

    test 'events are returned oldest first regardless of physical row order' do
      created = create_customer_event
      aggregate_id = created.aggregate_id

      ordered_ids = 3.times.map do
        Customer::Events::CustomerUpdated.create!(aggregate_id:, email: 'x@example.com').id
      end
      ordered_ids.unshift(created.id)

      # Relocate the oldest rows in the heap so physical order no longer matches
      # insertion order; the association must still sort them chronologically.
      ActiveRecord::Base.connection.execute(
        "UPDATE rails_micro_event_sourcing_events SET metadata = '{}' " \
        "WHERE id IN (#{ordered_ids.first}, #{ordered_ids.second})"
      )

      assert_equal ordered_ids, Customer.find(aggregate_id).events.pluck(:id)
    end

    private

    def create_customer_event(first_name: 'John', last_name: 'Doe', email: 'john@example.com')
      Customer::Events::CustomerCreated.create!(first_name:, last_name:, email:)
    end
  end
end
