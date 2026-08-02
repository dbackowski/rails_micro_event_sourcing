# Concrete model that inherits its enforce_events_only! policy rather than
# declaring it. Reuses the accounts table — it exists only to exercise inheritance.
class Ledger < AuditedRecord
  self.table_name = 'accounts'
end
