class Customer
  module Events
    # An event with no aggregate_class: recorded in the audit log only, it does
    # not create or modify any model.
    class CustomerLoginFailed < RailsMicroEventSourcing::Event
      event_attributes :email
    end
  end
end
