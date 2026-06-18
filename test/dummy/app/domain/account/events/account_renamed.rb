class Account
  module Events
    # Proves an enforce_events_only! model can still be modified through events.
    class AccountRenamed < RailsMicroEventSourcing::Event
      aggregate_class Account
      event_attributes :name

      validates :name, presence: true
    end
  end
end
