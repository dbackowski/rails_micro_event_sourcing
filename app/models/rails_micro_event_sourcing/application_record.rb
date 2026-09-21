# frozen_string_literal: true

module RailsMicroEventSourcing
  # Without this, `class Event < ApplicationRecord` resolves to the *host app's*
  # ApplicationRecord, and the engine inherits whatever lives there — a
  # `default_scope` from discard/acts_as_paranoid would silently filter the
  # append-only audit log. It also breaks outright in a host that has no
  # ::ApplicationRecord at all.
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
