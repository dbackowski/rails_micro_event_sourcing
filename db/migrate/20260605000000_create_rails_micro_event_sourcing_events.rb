# frozen_string_literal: true

class CreateRailsMicroEventSourcingEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :rails_micro_event_sourcing_events do |t|
      t.string :type, null: false
      t.references :eventable, polymorphic: true
      t.jsonb :payload, null: false, default: {}
      t.jsonb :metadata

      t.datetime :created_at, null: false

      t.index :type
    end
  end
end
