# CLAUDE.md

Guidance for working in this repo. See [README.md](README.md) for the user-facing docs.

## What this is

`rails_micro_event_sourcing` — a Rails engine gem. Minimal event sourcing where
**the event *is* the model**: one `ActiveRecord` subclass per event, which validates
itself and, on create, applies its payload to the aggregate and stores the audit row
in a single transaction. No commands, handlers, bus, snapshots, replay, or web UI.

The aggregate row is the current state. Events are an append-only audit log that is
never replayed.

## Commands

Tests need PostgreSQL on port 5435 (see [docker-compose.yml](docker-compose.yml)):

```bash
docker compose up -d postgres
bin/rails db:prepare          # runs against test/dummy
bundle exec rake test         # all tests
bundle exec ruby -Itest test/models/event_test.rb   # one file
bundle exec rubocop
```

`bin/rails` is the engine's Rails CLI; it boots `test/dummy` as the host app.

## Layout

| Path | What |
|---|---|
| [app/models/rails_micro_event_sourcing/event.rb](app/models/rails_micro_event_sourcing/event.rb) | The whole write path. Everything of substance lives here. |
| [app/models/concerns/rails_micro_event_sourcing/eventable.rb](app/models/concerns/rails_micro_event_sourcing/eventable.rb) | `include` on an aggregate: adds `events`, `enforce_events_only!` |
| [app/models/concerns/rails_micro_event_sourcing/read_only.rb](app/models/concerns/rails_micro_event_sourcing/read_only.rb) | Write guard — `readonly?` unless write access is explicitly opened |
| [app/models/rails_micro_event_sourcing/current_request.rb](app/models/rails_micro_event_sourcing/current_request.rb) | `ActiveSupport::CurrentAttributes` holding `metadata` |
| [app/models/rails_micro_event_sourcing/application_record.rb](app/models/rails_micro_event_sourcing/application_record.rb) | Engine-owned abstract base — keeps `Event` off the host's `ApplicationRecord` |
| [db/migrate/](db/migrate/) | The single `rails_micro_event_sourcing_events` table |
| [lib/](lib/) | Engine boilerplate + version only |
| [test/dummy/](test/dummy/) | Host app: models in `app/models`, event classes in `app/domain/<Model>/events/` |

`Event` is deliberately the centre of gravity — `.rubocop.yml` raises
`Metrics/ClassLength` for it rather than splitting it. Don't "fix" that by extracting
service objects.

## The write path

`Event.create` on a class with an `aggregate_class`, in callback order:

1. `before_validation` — clear the memoized aggregate.
2. `validate :aggregate_must_be_valid` — build/load the aggregate, `apply` the payload,
   run its validations; failures are merged into `event.errors`.
3. `before_create :capture_metadata` — copies `CurrentRequest.metadata` if unset.
4. `before_create :apply_to_aggregate` — saves the aggregate, links `eventable`.

The event's own immutability is not a callback: `Event#readonly?` is `super ||
persisted?`, so it is writable while being created and locked the instant it lands —
true on paths that skip validation too, e.g. `save(validate: false)`.

Existing aggregates are loaded with `aggregate_class.lock.find` (`SELECT … FOR UPDATE`),
so concurrent writers to one aggregate serialize.

## Invariants — break these and it fails silently

- **The aggregate is memoized per save attempt, not per event object.** `reset_aggregate_record`
  must clear it on every validation pass, or a payload edited after a failed `save` or
  an explicit `valid?` never reaches the model. Covered by
  [event_revalidation_test.rb](test/models/event_revalidation_test.rb).
- **`event_attributes` defines methods on the event class**, so a declared name matching
  a real column (`metadata`, `payload`, `type`, `created_at`) shadows that column's
  accessor. Internals must use `self[:payload]` / `read_attribute` — never the public
  reader. See [attribute_shadowing_test.rb](test/models/attribute_shadowing_test.rb).
- **`aggregate_class` and `event_attributes` both inherit** through subclasses. Walking
  `superclass` in the class methods is load-bearing; without it a subclass degrades into
  an aggregate-less audit row. See [event_inheritance_test.rb](test/models/event_inheritance_test.rb).
- **`enforce_events_only!` inherits too** (`class_attribute`), so declaring it on an
  abstract base carries to concrete models (`AuditedRecord` → `Ledger`).
- **`apply` raises `ArgumentError` on a missing setter** rather than dropping the value.
  Keep it loud — a renamed column must fail, not blank a field.
- **`aggregate_id` is virtual, not a column.** As input it names the record to load; as
  output it mirrors `eventable_id`.
- **`backfill!` does not apply onto the aggregate** — it only inserts a backdated audit
  row (full-attribute snapshot, `created_at` from the record), and returns `nil` if the
  aggregate already has *any* event. Idempotent by design. The guard is on the base
  `Event` scope, not `self`: scoped per-type it let a second, differently-typed
  backfill insert another genesis snapshot sorting ahead of real history.
- **`Event` inherits the engine's own `ApplicationRecord`**, not the host app's.
  `class Event < ApplicationRecord` resolves by lexical nesting, so deleting
  [app/models/rails_micro_event_sourcing/application_record.rb](app/models/rails_micro_event_sourcing/application_record.rb)
  silently reparents it onto the host's — where a `default_scope` (discard,
  acts_as_paranoid) would filter the append-only log with nothing raised. `test/dummy`
  defines `ApplicationRecord`, so only
  [base_class_test.rb](test/models/base_class_test.rb) catches this.

## Conventions

- Ruby >= 3.2, Rails >= 7.1, PostgreSQL only (`jsonb` payload/metadata).
- `# frozen_string_literal: true` on every gem file; rubocop excludes `test/dummy`,
  `bin`, and `db/migrate`.
- Tests are Minitest under `test/models/`, one file per behaviour area, each with a
  class-level comment explaining *why* the behaviour matters. Match that style: new
  behaviour gets a test file whose comment states the failure mode it guards.
- Keep the gem additive — including `Eventable` must not change a model's behaviour
  until `enforce_events_only!` is called.
