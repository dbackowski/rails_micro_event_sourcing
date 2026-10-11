# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # Destroying an aggregate must leave its audit rows exactly as written. The
  # `events` association used to be `dependent: :nullify`, so every destroy ran
  # an UPDATE blanking eventable_id/eventable_type: the gem rewrote its own
  # append-only log, a deleted record's history could no longer be found by id,
  # and under the insert-only grant the README recommends the UPDATE was
  # refused — failing the destroy of any Eventable model, events or not.
  class AggregateDestroyTest < ActiveSupport::TestCase
    def setup
      @customer = Customer::Events::CustomerCreated.create!(
        first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com'
      ).aggregate
    end

    test 'destroying an aggregate keeps its events linked to the id it had' do
      @customer.destroy!

      event = Event.find_by!(eventable_type: 'Customer', eventable_id: @customer.id)

      assert_nil event.eventable
      assert_equal @customer.id, event.aggregate_id
    end

    test 'destroying an aggregate writes nothing to the events table' do
      writes = events_table_writes { @customer.destroy! }

      assert_empty writes
    end

    test 'destroying an aggregate with no events writes nothing to the events table' do
      bare = Customer.create!(first_name: 'No', last_name: 'History', email: 'bare@example.com')

      assert_empty(events_table_writes { bare.destroy! })
    end

    private

    def events_table_writes(&)
      statements = []
      capture = ->(*, payload) { statements << payload[:sql] }
      ActiveSupport::Notifications.subscribed(capture, 'sql.active_record', &)
      statements.grep(/\A(UPDATE|DELETE)\b.*#{Event.table_name}/m)
    end
  end
end
