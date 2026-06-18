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

    private

    def create_customer_event(first_name: 'John', last_name: 'Doe', email: 'john@example.com')
      Customer::Events::CustomerCreated.create!(first_name:, last_name:, email:)
    end
  end
end
