require 'timescaledb'
require 'scenic'

ActiveSupport.on_load(:active_record) { extend Timescaledb::ActsAsHypertable }

