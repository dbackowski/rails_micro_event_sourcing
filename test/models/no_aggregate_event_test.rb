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
  end
end
