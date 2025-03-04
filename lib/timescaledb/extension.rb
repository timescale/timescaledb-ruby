module Timescaledb

  # Provides metadata around the extension in the database
  module Extension
    module_function
    # @return String version of the timescaledb extension
    def version
      @version ||= Timescaledb.connection.query_first(<<~SQL)&.version
        SELECT extversion as version
        FROM pg_extension
        WHERE extname = 'timescaledb'
      SQL
    end

    def installed?
      version.present?
    end

    def update!
      Timescaledb.connection.query_first('ALTER EXTENSION timescaledb UPDATE')
    end
  end
end
