# ruby compare_volatility.rb postgres://user:pass@host:port/db_name
require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb', path:  '../..'
  gem 'pry'
end

# TODO: get the volatility using the window function with plain postgresql

ActiveRecord::Base.establish_connection ARGV.last

# Compare volatility processing in Ruby vs SQL.
class Measurement < ActiveRecord::Base
  acts_as_hypertable time_column: "ts",
    segment_by: "device_id",
    value_column: "val"

  scope :volatility_sql, -> do
    select("device_id, timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> sum() as volatility")
     .group("device_id")
  end

  scope :volatility_ruby, -> {
    volatility = Hash.new(0)
    previous = Hash.new
    find_all do |measurement|
      device_id = measurement.device_id
      if previous[device_id]
        delta = (measurement.val - previous[device_id]).abs
        volatility[device_id] += delta
      end
      previous[device_id] = measurement.val
    end
    volatility
  }
  scope :values_from_devices, -> {
    ordered_values = select(:val, :device_id).order(:ts)
    Hash[
      from(ordered_values)
      .group(:device_id)
      .pluck("device_id, array_agg(val)")
    ]
  }
end

class Volatility
  def self.process(values)
    previous = nil
    deltas = values.map do |value|
      if previous
        delta = (value - previous).abs
        volatility = delta
      end
      previous = value
      volatility
    end
    #deltas => [nil, 1, 1]
    deltas.shift
    volatility = deltas.sum
  end
  def self.process_values(map)
    map.transform_values(&method(:process))
  end
end

ActiveRecord::Base.connection.add_toolkit_to_search_path!


ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  unless Measurement.table_exists?
    hypertable_options = {
      time_column: 'ts',
      chunk_time_interval: '1 day',
    }
    create_table :measurements, hypertable: hypertable_options, id: false do |t|
      t.integer :device_id
      t.decimal :val
      t.timestamp :ts
    end
  end
end

if Measurement.count.zero?
  ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO measurements (ts, device_id, val)
        SELECT ts, device_id, random()*80
      FROM generate_series(TIMESTAMP '2022-01-01 00:00:00',
                            TIMESTAMP '2022-02-01 00:00:00',
                            INTERVAL '5 minutes') AS g1(ts),
        generate_series(0, 5) AS g2(device_id);
     SQL
end


volatilities = nil
#ActiveRecord::Base.logger = nil
Benchmark.bm do |x|
  x.report("sql") { Measurement.volatility_sql.map(&:attributes)  }
  x.report("ruby")  { Measurement.volatility_ruby }
  x.report("fetch") { volatilities =  Measurement.values_from_devices }
  x.report("process") { Volatility.process_values(volatilities) }
end
