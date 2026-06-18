class Customer
  module Events
    # Only the attributes present in the payload are applied, so this can be used
    # for partial updates (the persisted row keeps everything else unchanged).
    class CustomerUpdated < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email
    end
  end
end
