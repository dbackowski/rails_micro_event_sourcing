# frozen_string_literal: true

module RailsMicroEventSourcing
  class CurrentRequest < ActiveSupport::CurrentAttributes
    attribute :metadata
  end
end
