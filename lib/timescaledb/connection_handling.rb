module Timescaledb
  class ConnectionNotEstablishedError < StandardError; end

  module_function
  
  # @param [String] config with the postgres connection string.
  def establish_connection(config)
    # Establish connection for Timescaledb
    Connection.instance.config = config
    
    # Also establish connection for ActiveRecord if it's defined
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.establish_connection(config)
    end
  end

  # @param [PG::Connection] to use it directly from a raw connection
  def use_connection(conn)
    Connection.instance.use_connection(conn)
    
    # Also set ActiveRecord connection if it's defined
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      # Get the existing connection handler and update it
      ar_conn = ActiveRecord::Base.connection
      ar_conn.instance_variable_set(:@raw_connection, conn)
    end
  end

  def connection
    raise ConnectionNotEstablishedError.new unless Connection.instance.connected?

    Connection.instance
  end
end
