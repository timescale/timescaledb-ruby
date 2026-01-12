# frozen_string_literal: true

module Timescaledb
  class Configuration
    attr_accessor :scenic_integration

    DEFAULTS = {
      scenic_integration: :enabled
    }.freeze

    def initialize
      @scenic_integration = DEFAULTS[:scenic_integration]
    end

    def enable_scenic_integration?
      case @scenic_integration
      when :enabled then scenic_detected?
      else false # :disabled, :false, nil, etc.
      end
    end

    private

    def scenic_detected?
      # Try to require scenic to see if it's available
      require 'scenic'
      true
    rescue LoadError
      false
    end
  end
end
