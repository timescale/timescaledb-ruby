# frozen_string_literal: true

module Timescaledb
  class Railtie
    def self.start
      # Ensure all modules are loaded before extending/including them
      require_relative 'acts_as_hypertable'
      require_relative 'acts_as_hypertable/core'
      require_relative 'connection_handling'
      require_relative 'counter_cache'

      # First extend with ActsAsHypertable
      ActiveSupport.on_load(:active_record) do
        extend Timescaledb::ActsAsHypertable
      end

      # Then include ConnectionHandling
      ActiveSupport.on_load(:active_record) do
        include Timescaledb::ConnectionHandling
      end

      # Include CounterCache
      ActiveSupport.on_load(:active_record) do
        include Timescaledb::CounterCache
      end

      if defined?(Rails) && Rails.application
        Rails.application.config.after_initialize do
          load File.expand_path('../tasks/timescaledb.rake', __dir__) if defined?(Rake)
        end
      elsif defined?(Rake)
        # Load rake tasks in non-Rails environment if Rake is defined
        load File.expand_path('../tasks/timescaledb.rake', __dir__)
      end
    end
  end
end

# Start the integration if Rails is present
if defined?(Rails)
  Timescaledb::Railtie.start
end 