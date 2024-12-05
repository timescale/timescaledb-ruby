# ruby ohlc.rb postgres://user:pass@host:port/db_name
# @see https://jonatas.github.io/timescaledb/ohlc_tutorial

require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb', path:  '../..'
  gem 'pry'
end

ActiveRecord::Base.establish_connection ARGV.last

# Compare ohlc processing in Ruby vs SQL.
class Tick < ActiveRecord::Base
  acts_as_hypertable time_column: "time"
  acts_as_time_vector segment_by: "symbol", value_column: "price"
end
require "active_support/concern"

module Ohlc
  extend ActiveSupport::Concern

  included do
    %w[open high low close].each do |name|
      attribute name, :decimal
      attribute "#{name}_time", :time
    end


    scope :attributes, -> do
      select("symbol, time,
        toolkit_experimental.open(ohlc),
        toolkit_experimental.high(ohlc),
        toolkit_experimental.low(ohlc),
        toolkit_experimental.close(ohlc),
        toolkit_experimental.open_time(ohlc),
        toolkit_experimental.high_time(ohlc),
        toolkit_experimental.low_time(ohlc),
        toolkit_experimental.close_time(ohlc)")
    end

    scope :rollup, -> (timeframe: '1h') do
      select("symbol, time_bucket('#{timeframe}', time) as time,
            toolkit_experimental.rollup(ohlc) as ohlc")
      .group(1,2)
    end

    def readonly?
      true
    end
  end

  class_methods do
  end
end

class Ohlc1m < ActiveRecord::Base
  self.table_name = 'ohlc_1m'
  include Ohlc
end

class Ohlc1h < ActiveRecord::Base
  self.table_name = 'ohlc_1h'
  include Ohlc
end

class Ohlc1d < ActiveRecord::Base
  self.table_name = 'ohlc_1d'
  include Ohlc
end

ActiveRecord::Base.connection.add_toolkit_to_search_path!


ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  unless Tick.table_exists?
    hypertable_options = {
      time_column: 'time',
      chunk_time_interval: '1 week',
      compress_segmentby: 'symbol',
      compress_orderby: 'time',
      compress_after: '1 month'
    }
    create_table :ticks, hypertable: hypertable_options, id: false do |t|
      t.column :time , 'timestamp with time zone'
      t.string :symbol
      t.decimal :price
      t.integer :volume
    end

    options = {
      with_data: false,
      refresh_policies: {
        start_offset: "INTERVAL '1 month'",
        end_offset: "INTERVAL '1 minute'",
        schedule_interval: "INTERVAL '1 minute'"
      }
    }
    create_continuous_aggregate('ohlc_1m', Tick._candlestick(timeframe: '1m'), **options)

    execute "CREATE VIEW ohlc_1h AS #{ Ohlc1m.rollup(timeframe: '1 hour').to_sql}"
    execute "CREATE VIEW ohlc_1d AS #{ Ohlc1h.rollup(timeframe: '1 day').to_sql}"
  end
end

if Tick.count.zero?
  ActiveRecord::Base.connection.execute(<<~SQL)
    INSERT INTO ticks
    SELECT time, 'SYMBOL', 1 + (random()*30)::int, 100*(random()*10)::int
    FROM generate_series(TIMESTAMP '2022-01-01 00:00:00',
                    TIMESTAMP '2022-02-01 00:01:00',
                INTERVAL '1 second') AS time;
     SQL
end


# Fetch attributes
Ohlc1m.attributes

# Rollup demo

# Attributes from rollup
Ohlc1m.attributes.from(Ohlc1m.rollup(timeframe: '1 day'))


# Nesting several levels
Ohlc1m.attributes.from(
  Ohlc1m.rollup(timeframe: '1 week').from(
    Ohlc1m.rollup(timeframe: '1 day')
  )
)
Ohlc1m.attributes.from(
  Ohlc1m.rollup(timeframe: '1 month').from(
    Ohlc1m.rollup(timeframe: '1 week').from(
      Ohlc1m.rollup(timeframe: '1 day')
    )
  )
)

Pry.start

=begin
TODO: implement the ohlc_ruby 
Benchmark.bm do |x|
  x.report("ruby")  { Tick.ohlc_ruby }
  x.report("sql") { Tick.ohlc.map(&:attributes)  }
end
=end
