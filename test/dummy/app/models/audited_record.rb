# Declaring the policy once on a shared abstract base is the natural way to adopt
# the gem across several models, so it has to carry down to the concrete classes.
class AuditedRecord < ApplicationRecord
  self.abstract_class = true

  include RailsMicroEventSourcing::Eventable
  enforce_events_only!
end
