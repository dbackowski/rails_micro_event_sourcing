# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # An event can be validated more than once before it is saved: an explicit
  # `valid?` pre-check, or a retry after a failed save. The aggregate is memoized
  # per save attempt, not per event object, so every pass must re-read and
  # re-apply from the current payload and aggregate_id. When it doesn't, the event
  # row and the model row diverge silently.
  class EventRevalidationTest < ActiveSupport::TestCase
    test 'a payload change after a failed save reaches the aggregate' do
      create_customer_event(email: 'taken@example.com')

      event = Customer::Events::CustomerCreated.new(
        first_name: 'Jane', last_name: 'Roe', email: 'taken@example.com'
      )
      assert_not event.save

      event.email = 'free@example.com'

      assert event.save, event.errors.full_messages.to_sentence
      assert_equal 'free@example.com', event.aggregate.reload.email
    end

    test 'a payload change after an explicit valid? is not silently dropped' do
      event = Customer::Events::CustomerCreated.new(first_name: 'A', last_name: 'B', email: 'a@example.com')
      assert event.valid?

      event.email = 'b@example.com'
      event.save!

      assert_equal 'b@example.com', event.payload['email']
      assert_equal 'b@example.com', event.aggregate.reload.email
    end

    test 'an aggregate_id changed after an explicit valid? targets the new record' do
      first = create_customer_event(email: 'first@example.com').aggregate
      second = create_customer_event(email: 'second@example.com').aggregate

      event = Customer::Events::CustomerUpdated.new(aggregate_id: first.id, first_name: 'Changed')
      assert event.valid?

      event.aggregate_id = second.id
      event.save!

      assert_equal second.id, event.aggregate_id
      assert_equal 'Changed', second.reload.first_name
      assert_not_equal 'Changed', first.reload.first_name
    end

    private

    def create_customer_event(first_name: 'John', last_name: 'Doe', email: 'john@example.com')
      Customer::Events::CustomerCreated.create!(first_name:, last_name:, email:)
    end
  end
end
