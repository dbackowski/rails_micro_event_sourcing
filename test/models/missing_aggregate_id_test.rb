# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # The gem picks create or update from aggregate_id alone: blank builds a new
  # record. So an update event fed a missing param (`aggregate_id: params[:id]`
  # with no id) created a fresh record — silently with a full payload, a
  # NotNullViolation 500 with a partial one — and left the intended record
  # untouched. Update events declare `validates :aggregate_id, presence: true`
  # (README, Updates); this guards that the declaration turns it into a normal
  # validation failure with nothing written.
  class MissingAggregateIdTest < ActiveSupport::TestCase
    FULL = { first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com' }.freeze

    [nil, ''].each do |blank|
      test "an update event with aggregate_id #{blank.inspect} is invalid and writes nothing" do
        event = Customer::Events::CustomerUpdated.new(aggregate_id: blank, **FULL)

        assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
          assert_not event.save
        end
        assert_includes event.errors[:aggregate_id], "can't be blank"
      end
    end

    test 'a partial update with no aggregate_id returns false instead of hitting NOT NULL' do
      event = Customer::Events::CustomerUpdated.new(aggregate_id: nil, email: 'jane@example.com')

      assert_not event.save
      assert_includes event.errors[:aggregate_id], "can't be blank"
    end
  end
end
