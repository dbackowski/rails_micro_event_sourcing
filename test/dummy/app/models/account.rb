class Account < ApplicationRecord
  # Strict adoption: events are the ONLY way to modify this model.
  include RailsMicroEventSourcing::Eventable
  enforce_events_only!
end
