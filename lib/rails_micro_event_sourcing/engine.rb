# frozen_string_literal: true

module RailsMicroEventSourcing
  # A model-only engine: it ships the Event model, the aggregate concern, and a
  # migration. There are no routes, controllers, or views.
  class Engine < ::Rails::Engine
    isolate_namespace RailsMicroEventSourcing
  end
end
