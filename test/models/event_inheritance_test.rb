# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # Event classes are frequently subclassed to share attributes, validations, or
  # callbacks. Both `aggregate_class` and `event_attributes` must carry down the
  # hierarchy — otherwise a subclass silently degrades into an aggregate-less
  # audit row (see the three variants below).
  class EventInheritanceTest < ActiveSupport::TestCase
    # Variant A: everything declared on the base, empty subclass.
    class BaseCustomerEvent < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email
    end

    class InheritedCustomerCreated < BaseCustomerEvent; end

    # Variant B: attributes on the base, aggregate_class re-declared on the child.
    class AttrsOnlyBase < RailsMicroEventSourcing::Event
      event_attributes :first_name, :last_name, :email
    end

    class RedeclaredAggregateCreated < AttrsOnlyBase
      aggregate_class Customer
    end

    # Variant C: aggregate_class + some attributes on the base, more on the child.
    class PartialBase < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :email
    end

    class ExtendedCreated < PartialBase
      event_attributes :first_name, :last_name
    end

    test 'variant A: an empty subclass inherits aggregate_class and attributes and materializes the aggregate' do
      event = InheritedCustomerCreated.create!(first_name: 'Ada', last_name: 'Lovelace', email: 'ada@example.com')

      customer = event.aggregate
      assert_instance_of Customer, customer
      assert customer.persisted?
      assert_equal 'Ada', customer.first_name
      assert_equal 'Lovelace', customer.last_name
      assert_equal [event], customer.events.to_a
    end

    test 'variant B: a subclass that re-declares aggregate_class still applies inherited attributes' do
      event = RedeclaredAggregateCreated.create!(first_name: 'Grace', last_name: 'Hopper', email: 'grace@example.com')

      customer = event.aggregate
      assert_instance_of Customer, customer
      assert_equal 'Grace', customer.first_name
      assert_equal 'Hopper', customer.last_name
    end

    test 'variant C: a subclass applies both inherited and its own attributes' do
      event = ExtendedCreated.create!(email: 'alan@example.com', first_name: 'Alan', last_name: 'Turing')

      customer = event.aggregate
      assert_instance_of Customer, customer
      assert_equal 'Alan', customer.first_name
      assert_equal 'Turing', customer.last_name
      assert_equal 'alan@example.com', customer.email
    end

    test 'event_attribute_names combines ancestor and own declarations without duplicates' do
      assert_equal %w[email first_name last_name], ExtendedCreated.event_attribute_names
    end

    test 'a child adding attributes does not leak them back onto its parent' do
      assert_equal %w[email], PartialBase.event_attribute_names
    end

    test 'aggregate_class is inherited by an empty subclass' do
      assert_equal Customer, InheritedCustomerCreated.aggregate_class
    end
  end
end
