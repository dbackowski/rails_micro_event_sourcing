# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  class NoAggregateEventTest < ActiveSupport::TestCase
    test 'an event without an aggregate_class is persisted to the audit log only' do
      event = Customer::Events::CustomerLoginFailed.create!(email: 'john@example.com')

      assert event.persisted?
      assert_nil event.aggregate
      assert_nil event.aggregate_id
      assert_equal({ 'email' => 'john@example.com' }, event.payload)
    end

    test 'it does not create any aggregate record' do
      assert_no_difference 'Customer.count' do
        Customer::Events::CustomerLoginFailed.create!(email: 'john@example.com')
      end
    end

    # With no aggregate_class there is nothing to resolve the id against, so it
    # used to be accepted and dropped: the caller wanted the event in
    # `customer.events`, got no link, and found out much later. Fail at the
    # call site instead, and name the option that does what they meant.
    test 'an aggregate_id on an aggregate-less event raises, pointing at eventable:' do
      error = assert_raises(ArgumentError) do
        Customer::Events::CustomerLoginFailed.new(email: 'john@example.com', aggregate_id: 999)
      end

      assert_match(/no aggregate_class/, error.message)
      assert_match(/eventable:/, error.message)
    end

    test 'a blank aggregate_id is still accepted, so generic callers passing nil keep working' do
      event = Customer::Events::CustomerLoginFailed.create!(email: 'john@example.com', aggregate_id: nil)

      assert_nil event.aggregate_id
    end

    test 'eventable: links the event to a record without changing it' do
      customer = Customer::Events::CustomerCreated.create!(
        first_name: 'John', last_name: 'Doe', email: 'john@example.com'
      ).aggregate

      assert_no_changes -> { customer.reload.updated_at } do
        Customer::Events::CustomerLoginFailed.create!(eventable: customer, email: 'john@example.com')
      end

      assert_equal(%w[CustomerCreated CustomerLoginFailed], customer.events.map { |e| e.class.name.demodulize })
    end
  end
end
