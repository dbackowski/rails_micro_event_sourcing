# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # An aggregate_id naming no record is a validation error. The rescue that
  # turns it into one used to wrap the whole validation — the event's `apply`
  # and the aggregate's own validations too — so a RecordNotFound from any
  # lookup in there became "Aggregate does not reference an existing record":
  # blamed on an aggregate_id that was valid, or on a create event that had
  # none, with the real message discarded and the bug reported as bad input
  # instead of reaching the error tracker.
  class AggregateNotFoundTest < ActiveSupport::TestCase
    class CustomerSignedUp < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email

      def apply(customer)
        super
        customer.last_name = "#{customer.last_name} @ #{Account.find_by!(name: 'Default').name}"
      end
    end

    class CustomerReferred < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :referrer_id

      def apply(customer)
        customer.last_name = "#{customer.last_name} (ref #{Customer.find(referrer_id).email})"
      end
    end

    class InvitedCustomer < Customer
      attr_accessor :invited_by

      validate { Customer.find(invited_by) if invited_by }
    end

    class CustomerInvited < RailsMicroEventSourcing::Event
      aggregate_class InvitedCustomer

      def apply(customer)
        customer.invited_by = 0
      end
    end

    def setup
      @customer = Customer::Events::CustomerCreated.create!(
        first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com'
      ).aggregate
    end

    test 'a missing aggregate_id record is still a validation error' do
      event = Customer::Events::CustomerUpdated.new(aggregate_id: 0, email: 'new@example.com')

      assert_not event.save
      assert_includes event.errors[:aggregate_id], 'does not reference an existing record'
    end

    test 'a failed lookup in apply on a create event raises with its own message' do
      error = assert_raises(ActiveRecord::RecordNotFound) do
        CustomerSignedUp.new(first_name: 'A', last_name: 'B', email: 'a@example.com').save
      end

      assert_equal 'Account', error.model
    end

    test 'a failed lookup in apply raises when the aggregate_id is valid' do
      error = assert_raises(ActiveRecord::RecordNotFound) do
        CustomerReferred.new(aggregate_id: @customer.id, referrer_id: 0).save
      end

      assert_match(/Couldn't find Customer with 'id'=0/, error.message)
    end

    test "a failed lookup in the aggregate's own validation raises" do
      error = assert_raises(ActiveRecord::RecordNotFound) do
        CustomerInvited.new(aggregate_id: @customer.id).save
      end

      assert_match(/Couldn't find Customer with 'id'=0/, error.message)
    end

    test 'nothing is written when a lookup inside the event fails' do
      assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_raises(ActiveRecord::RecordNotFound) do
          CustomerSignedUp.create(first_name: 'A', last_name: 'B', email: 'a@example.com')
        end
      end
    end
  end
end
