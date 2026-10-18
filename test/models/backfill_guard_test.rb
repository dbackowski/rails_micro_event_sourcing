# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

module RailsMicroEventSourcing
  # A backfilled genesis row cannot be taken back — the README's insert-only
  # grant forbids DELETE, and backfill! skips any aggregate that already has an
  # event — so a wrong one is permanent. backfill! used to write whatever it
  # was handed: a record of another class (which then blocked the right
  # backfill), a class without Eventable, and a snapshot of the caller's
  # in-memory object, unsaved edits included.
  class BackfillGuardTest < ActiveSupport::TestCase
    class LegacyCustomerCreated < RailsMicroEventSourcing::Event
      aggregate_class LegacyCustomer
    end

    # Stands in for discard/acts_as_paranoid: soft-deleted rows still get a history.
    class ScopedCustomer < Customer
      default_scope { where.not(last_name: 'Discarded') }
    end

    class ScopedCustomerCreated < RailsMicroEventSourcing::Event
      aggregate_class ScopedCustomer
    end

    def setup
      @customer = Customer.create!(first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com')
    end

    test 'a record of another class raises and writes nothing' do
      account = Account.new(name: 'Acme').tap(&:enable_write_access!).tap(&:save!)

      error = assert_raises(ArgumentError) { Customer::Events::CustomerCreated.backfill!(account) }

      assert_match(/backfills Customer, not Account/, error.message)
      assert_empty account.events
    end

    test 'an aggregate_class without Eventable raises and writes nothing' do
      legacy = LegacyCustomer.find(@customer.id)

      assert_no_difference 'RailsMicroEventSourcing::Event.count' do
        error = assert_raises(ArgumentError) { LegacyCustomerCreated.backfill!(legacy) }
        assert_match(/LegacyCustomer does not include RailsMicroEventSourcing::Eventable/, error.message)
      end
    end

    test 'the snapshot is read from the row, not from unsaved changes on the object' do
      @customer.first_name = 'Never saved'
      Customer::Events::CustomerCreated.backfill!(@customer)

      assert_equal 'Jane', @customer.events.sole.payload['first_name']
    end

    test 'a record hidden by default_scope is still backfilled' do
      @customer.update!(last_name: 'Discarded')
      hidden = ScopedCustomer.unscoped.find(@customer.id)

      ScopedCustomerCreated.backfill!(hidden)

      assert_equal 'Discarded', @customer.events.sole.payload['last_name']
    end
  end

  # Idempotency has to hold for runs that overlap, not only for runs in
  # sequence: the same task started on two hosts, or a job enqueued twice. The
  # check and the insert used to be separate statements with no lock, so both
  # runs saw an empty history and both inserted a genesis row.
  class BackfillConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    def setup
      @customer = Customer.create!(first_name: 'Race', last_name: 'R', email: 'race@example.com')
    end

    def teardown
      Event.where(eventable_type: 'Customer', eventable_id: @customer.id).delete_all
      @customer.delete
    end

    test 'two backfills of one record at once write a single genesis row' do
      run_concurrently(2) { Customer::Events::CustomerCreated.backfill!(Customer.find(@customer.id)) }

      assert_equal 1, Event.where(eventable_type: 'Customer', eventable_id: @customer.id).count
    end

    private

    # Holds each run just after its existence check until the other has made
    # its own, so an unserialized check-then-insert always races. Serialized
    # runs cannot meet there; the wait times out and they go in turn.
    def run_concurrently(count, &)
      barrier = Concurrent::CyclicBarrier.new(count)
      exists = Event.method(:exists?)
      held_exists = ->(*args, **kwargs) { exists.call(*args, **kwargs).tap { barrier.wait(0.5) } }

      Event.stub(:exists?, held_exists) do
        Array.new(count) { Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) } }.each(&:join)
      end
    end
  end
end
