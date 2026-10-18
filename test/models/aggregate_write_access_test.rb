# frozen_string_literal: true

require 'test_helper'

module RailsMicroEventSourcing
  # Write access to an enforce_events_only! aggregate is opened only for the
  # event's own save of it. It used to be closed by the line after that save,
  # so any exception from it — a unique or NOT NULL violation, a deadlock, a
  # raising callback — left the object writable. The aggregate's after_rollback
  # then runs on that object after the transaction is gone, and a write there
  # committed straight to an enforced model, with no event in the log.
  class AggregateWriteAccessTest < ActiveSupport::TestCase
    class FailingAccount < Account
      cattr_accessor :rollback_write_error

      # Fails after the UPDATE has run, which is what makes Rails fire after_rollback.
      after_save { raise ActiveRecord::Deadlocked, 'simulated' if name == 'fail' }

      after_rollback do
        next if @rollback_write_attempted

        @rollback_write_attempted = true
        begin
          update!(name: 'written after rollback')
        rescue ActiveRecord::ReadOnlyRecord => e
          self.class.rollback_write_error = e
        end
      end
    end

    class FailingAccountRenamed < RailsMicroEventSourcing::Event
      aggregate_class FailingAccount
      event_attributes :name
    end

    def setup
      FailingAccount.rollback_write_error = nil
      @account = Account::Events::AccountCreated.create!(name: 'original').aggregate
    end

    test 'the aggregate is not writable from after_rollback once the event fails' do
      assert_raises(ActiveRecord::Deadlocked) { rename_in_savepoint }

      assert_instance_of ActiveRecord::ReadOnlyRecord, FailingAccount.rollback_write_error
      assert_equal 'original', @account.reload.name
    end

    test 'nothing reaches the log when the event fails' do
      assert_no_difference 'RailsMicroEventSourcing::Event.count' do
        assert_raises(ActiveRecord::Deadlocked) { rename_in_savepoint }
      end
    end

    private

    # A savepoint of its own, so the rollback callbacks fire inside the test's transaction.
    def rename_in_savepoint
      Event.transaction(requires_new: true) do
        FailingAccountRenamed.create!(aggregate_id: @account.id, name: 'fail')
      end
    end
  end
end
