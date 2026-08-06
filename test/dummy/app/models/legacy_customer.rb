# Deliberately does NOT include RailsMicroEventSourcing::Eventable — it stands in
# for a model someone points an event at before adopting the concern on it.
class LegacyCustomer < ApplicationRecord
  self.table_name = 'customers'
end
