class Customer
  module Events
    class CustomerCreated < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email

      validates :first_name, presence: true
      validates :last_name, presence: true
      validates :email, presence: true
    end
  end
end
