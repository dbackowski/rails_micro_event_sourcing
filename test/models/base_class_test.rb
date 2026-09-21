# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # `class Event < ApplicationRecord` resolves by lexical nesting, so without an
  # engine-owned base class it silently picks up the *host app's*. A host
  # `default_scope` (discard, acts_as_paranoid) would then filter the
  # append-only audit log with nothing raised, and a host with no
  # ::ApplicationRecord at all would fail to boot the engine.
  class BaseClassTest < ActiveSupport::TestCase
    test 'Event does not descend from the host application base class' do
      assert_not_operator Event, :<, ::ApplicationRecord
    end

    test 'Event descends from the engine base class' do
      assert_operator Event, :<, RailsMicroEventSourcing::ApplicationRecord
    end

    test 'the engine base class is abstract' do
      assert_predicate RailsMicroEventSourcing::ApplicationRecord, :abstract_class?
    end
  end
end
