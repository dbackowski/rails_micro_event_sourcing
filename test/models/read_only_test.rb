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
  end
end
