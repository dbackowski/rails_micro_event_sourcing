# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # backfill! dates the genesis row from the record's created_at, falling back
  # to now. It used to call `aggregate.created_at`, which raises NoMethodError
  # on a table made without timestamps — before the fallback was reached — so a
  # `find_each { backfill! }` adoption run stopped at the first such record.
  class BackfillWithoutTimestampsTest < ActiveSupport::TestCase
    class Tag < ApplicationRecord
      self.table_name = 'timestampless_tags'
      include RailsMicroEventSourcing::Eventable
    end

    class TagCreated < RailsMicroEventSourcing::Event
      aggregate_class Tag
    end

    # DDL is transactional in PostgreSQL, so the test's rollback drops the table.
    def setup
      ActiveRecord::Base.connection.create_table(:timestampless_tags) { |t| t.string :name }
      Tag.reset_column_information
      @tag = Tag.create!(name: 'ruby')
    end

    test 'a record with no created_at column is backfilled, dated now' do
      freeze_time do
        TagCreated.backfill!(@tag)

        event = TagCreated.find_by!(eventable_id: @tag.id)
        assert_equal Time.current, event.created_at
        assert_equal({ 'id' => @tag.id, 'name' => 'ruby' }, event.payload)
      end
    end
  end
end
