# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  class BackfillTest < ActiveSupport::TestCase
    CREATED_AT = Time.utc(2023, 11, 1, 17, 5, 53)
    UPDATED_AT = Time.utc(2024, 6, 14, 9, 12, 0)

    # A record that predates the gem: created via a plain manual write, no events.
    # The timestamps are backdated to stand in for its real (pre-gem) history.
    def setup
      @customer = Customer.create!(
        first_name: 'John', last_name: 'Doe', email: 'john@example.com',
        created_at: CREATED_AT, updated_at: UPDATED_AT
      )
    end

    test 'backfill writes a genesis event without touching the aggregate' do
      assert_no_changes -> { @customer.reload.updated_at } do
        Customer::Events::CustomerCreated.backfill!(@customer)
      end

      assert_equal [@customer], @customer.events.map(&:aggregate)
    end

    test 'the event carries a full snapshot of the record, including timestamps' do
      Customer::Events::CustomerCreated.backfill!(@customer)

      payload = @customer.events.sole.payload
      assert_equal 'John', payload['first_name']
      assert_equal 'Doe', payload['last_name']
      assert_equal 'john@example.com', payload['email']
      assert_equal @customer.id, payload['id']
      assert_equal @customer.updated_at, payload['updated_at']
    end

    test "the event's created_at is backdated to when the record was created" do
      Customer::Events::CustomerCreated.backfill!(@customer)

      assert_equal @customer.created_at, @customer.events.sole.created_at
    end

    test 'metadata is stored when provided' do
      Customer::Events::CustomerCreated.backfill!(@customer, metadata: { backfilled: true })

      assert_equal({ 'backfilled' => true }, @customer.events.sole.metadata)
    end

    test 'running backfill twice creates exactly one event' do
      Customer::Events::CustomerCreated.backfill!(@customer)

      assert_no_difference 'RailsMicroEventSourcing::Event.count' do
        assert_nil Customer::Events::CustomerCreated.backfill!(@customer)
      end
    end

    test 'backfill is skipped when a real creation event already exists' do
      real = Customer::Events::CustomerCreated.create!(first_name: 'Jane', last_name: 'Roe', email: 'jane@example.com')

      assert_no_difference 'RailsMicroEventSourcing::Event.count' do
        assert_nil Customer::Events::CustomerCreated.backfill!(real.aggregate)
      end
    end

    test 'backfill raises for an event type with no aggregate_class' do
      assert_raises(ArgumentError) do
        Customer::Events::CustomerLoginFailed.backfill!(@customer)
      end
    end
  end
end
