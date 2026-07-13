# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  class EventAttributesTest < ActiveSupport::TestCase
    # A deliberately mistyped event: Customer has `email`, not `emial`.
    class MistypedEvent < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :emial
    end

    test 'an event_attribute with no matching setter on the aggregate raises instead of silently dropping it' do
      error = assert_raises(ArgumentError) do
        MistypedEvent.create!(emial: 'jane@example.com')
      end

      assert_match(/MistypedEvent declares `event_attributes :emial`/, error.message)
      assert_match(/Customer has no #emial= setter/, error.message)
    end

    test 'nothing is written when an event_attribute is unmapped' do
      assert_no_difference ['Customer.count', 'RailsMicroEventSourcing::Event.count'] do
        assert_raises(ArgumentError) { MistypedEvent.create!(emial: 'jane@example.com') }
      end
    end
  end
end
