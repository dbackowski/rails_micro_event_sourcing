# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  class ReadOnlyTest < ActiveSupport::TestCase
    test 'a model without enforce_events_only! can still be modified directly' do
      event = Customer::Events::CustomerCreated.create!(first_name: 'John', last_name: 'Doe', email: 'john@example.com')

      customer = Customer.find(event.aggregate_id)
      customer.update!(first_name: 'Jane')

      assert_equal 'Jane', customer.reload.first_name
    end

    test 'a model with enforce_events_only! cannot be modified directly' do
      event = Account::Events::AccountCreated.create!(name: 'Acme')

      account = Account.find(event.aggregate_id)

      assert_raises(ActiveRecord::ReadOnlyRecord) { account.update!(name: 'Globex') }
    end

    test 'an enforce_events_only! model can still be modified through an event' do
      created = Account::Events::AccountCreated.create!(name: 'Acme')

      Account::Events::AccountRenamed.create!(aggregate_id: created.aggregate_id, name: 'Globex')

      assert_equal 'Globex', Account.find(created.aggregate_id).name
    end

    # The policy is declared on a class but read through subclasses: an STI child, or
    # a concrete model under a shared abstract base. If it does not carry down, the
    # guard silently fails open and writes land with no event recorded.
    class PremiumAccount < Account; end

    test 'enforce_events_only! is inherited by a subclass' do
      assert PremiumAccount.enforce_events_only?
    end

    test 'a subclass of an enforce_events_only! model cannot be modified directly' do
      created = Account::Events::AccountCreated.create!(name: 'Acme')

      assert_raises(ActiveRecord::ReadOnlyRecord) do
        PremiumAccount.find(created.aggregate_id).update!(name: 'Globex')
      end
    end

    test 'a subclass of an enforce_events_only! model can still be modified through an event' do
      created = Account::Events::AccountCreated.create!(name: 'Acme')

      Account::Events::AccountRenamed.create!(aggregate_id: created.aggregate_id, name: 'Globex')

      assert_equal 'Globex', PremiumAccount.find(created.aggregate_id).name
    end

    test 'enforce_events_only! declared on an abstract base carries down to concrete models' do
      assert Ledger.enforce_events_only?
    end

    test 'a model inheriting the policy from an abstract base cannot be modified directly' do
      created = Account::Events::AccountCreated.create!(name: 'Acme')

      assert_raises(ActiveRecord::ReadOnlyRecord) do
        Ledger.find(created.aggregate_id).update!(name: 'Globex')
      end
    end

    test 'declaring the policy on a subclass does not leak up to its parent' do
      assert_not Customer.enforce_events_only?
    end

    # The event's own write guard used to be opened by a before_validation hook,
    # so skipping validation left the event locked and the create failed with a
    # misleading ReadOnlyRecord instead of writing.
    test 'an event can be created with validations skipped' do
      event = Customer::Events::CustomerCreated.new(first_name: 'John', last_name: 'Doe', email: 'john@example.com')

      assert event.save(validate: false)
      assert_equal 'john@example.com', event.aggregate.email
    end

    test 'an event is immutable once persisted, however it was written' do
      event = Customer::Events::CustomerCreated.new(first_name: 'John', last_name: 'Doe', email: 'john@example.com')
      event.save(validate: false)

      assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(metadata: { tampered: true }) }
    end
  end
end
