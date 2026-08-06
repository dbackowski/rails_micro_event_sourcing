# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # Applying an event needs more from the aggregate than plain ActiveRecord: the
  # `events` association and the write guard both arrive with Eventable. Without
  # it the event still builds and validates, and only the write fails — so the
  # error has to name the missing include rather than the gem's internals.
  class AggregateClassTest < ActiveSupport::TestCase
    class LegacyCustomerCreated < RailsMicroEventSourcing::Event
      aggregate_class LegacyCustomer
      event_attributes :first_name, :last_name, :email
    end

    # Ledger inherits Eventable from the abstract AuditedRecord rather than
    # including it directly, which the check has to accept.
    class LedgerCreated < RailsMicroEventSourcing::Event
      aggregate_class Ledger
      event_attributes :name
    end

    test 'an aggregate_class that does not include Eventable raises a clear error' do
      error = assert_raises(ArgumentError) do
        LegacyCustomerCreated.create!(first_name: 'A', last_name: 'B', email: 'legacy@example.com')
      end

      assert_match(/LegacyCustomer/, error.message)
      assert_match(/does not include RailsMicroEventSourcing::Eventable/, error.message)
    end

    test 'nothing is written when the aggregate_class does not include Eventable' do
      assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_raises(ArgumentError) do
          LegacyCustomerCreated.create!(first_name: 'A', last_name: 'B', email: 'legacy@example.com')
        end
      end
    end

    test 'an aggregate_class inheriting Eventable from an abstract base is accepted' do
      event = LedgerCreated.create!(name: 'Acme')

      assert_equal 'Acme', event.aggregate.name
      assert_equal [event], event.aggregate.events.to_a
    end
  end
end
