class Customer < ApplicationRecord
  # Default adoption: audit log + event-driven writes, but manual writes still allowed.
  include RailsMicroEventSourcing::Eventable
end
