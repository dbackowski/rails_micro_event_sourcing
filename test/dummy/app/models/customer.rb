class Customer < ApplicationRecord
  # Default adoption: audit log + event-driven writes, but manual writes still allowed.
  include RailsMicroEventSourcing::Eventable

  # A model-level validation (backed by the unique index in the schema). Events
  # don't repeat it, so it exercises that aggregate validations surface on the event.
  validates :email, uniqueness: true
end
