class Customer
  module Events
    # Only the attributes present in the payload are applied, so this can be used
    # for partial updates (the persisted row keeps everything else unchanged).
    class CustomerUpdated < RailsMicroEventSourcing::Event
      aggregate_class Customer
      event_attributes :first_name, :last_name, :email

      # A blank aggregate_id means "build a new record"; an update must not do that.
      validates :aggregate_id, presence: true
    end
  end
end
