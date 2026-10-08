# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # An event with an aggregate_class finds its record by aggregate_id only.
  # Naming it any other way — eventable:, or building through `events` — used
  # to be ignored: the lookup saw no aggregate_id, built a brand-new record,
  # applied the "update" to that, and linked the event to it. The intended
  # record was left untouched and nothing raised. Each door must now fail
  # loudly, with no record created.
  class AggregateLookupTest < ActiveSupport::TestCase
    UPDATE = { first_name: 'Renamed', last_name: 'R', email: 'renamed@example.com' }.freeze

    def setup
      @owner = Customer::Events::CustomerCreated.create!(
        first_name: 'Owner', last_name: 'O', email: 'owner@example.com'
      ).aggregate
    end

    test 'aggregate_id: updates the named record' do
      Customer::Events::CustomerUpdated.create!(aggregate_id: @owner.id, **UPDATE)

      assert_equal 'Renamed', @owner.reload.first_name
    end

    test 'eventable: on an aggregate-backed event raises instead of building a new record' do
      assert_rejected { Customer::Events::CustomerUpdated.create!(eventable: @owner, **UPDATE) }
    end

    test 'building through the events association raises instead of building a new record' do
      assert_rejected { @owner.events.create!(type: Customer::Events::CustomerUpdated.name, **UPDATE) }
    end

    test 'eventable: a record of another class raises instead of being silently replaced' do
      account = Account::Events::AccountCreated.create!(name: 'Acme').aggregate

      assert_rejected { Customer::Events::CustomerUpdated.create!(eventable: account, **UPDATE) }
    end

    # belongs_to autosave runs before the lookup, so the unsaved record would
    # otherwise be written too — two customers from one event.
    test 'eventable: an unsaved record raises and creates nothing' do
      assert_rejected do
        Customer::Events::CustomerUpdated.create!(
          eventable: Customer.new(first_name: 'U', last_name: 'U', email: 'unsaved@example.com'), **UPDATE
        )
      end
    end

    test 'the error names aggregate_id: as the way to target a record' do
      error = assert_raises(ArgumentError) do
        Customer::Events::CustomerUpdated.create!(eventable: @owner, **UPDATE)
      end

      assert_match(/aggregate_id:/, error.message)
    end

    private

    def assert_rejected(&)
      assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_raises(ArgumentError, &)
      end
      assert_equal 'Owner', @owner.reload.first_name
    end
  end
end
