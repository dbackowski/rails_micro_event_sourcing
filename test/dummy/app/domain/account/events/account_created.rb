class Account
  module Events
    class AccountCreated < RailsMicroEventSourcing::Event
      aggregate_class Account
      event_attributes :name

      validates :name, presence: true
    end
  end
end
