require 'bundler/inline' #require only what you need

gemfile(true) do 
  gem 'timescaledb', path:  '../..'
  gem 'pry'
end

require 'pp'
# ruby caggs.rb postgres://user:pass@host:port/db_name
ActiveRecord::Base.establish_connection( ARGV.last)

class Tick < ActiveRecord::Base
  self.table_name = 'ticks'
  self.primary_key = nil

  acts_as_hypertable time_column: 'time'

  %w[open high low close].each{|name| attribute name, :decimal}

  scope :ohlc, -> (timeframe='1m') do
    select("time_bucket('#{timeframe}', time) as time,
      symbol,
      FIRST(price, time) as open,
      MAX(price) as high,
      MIN(price) as low,
      LAST(price, time) as close,
      SUM(volume) as volume").group("1,2")
  end
end

ActiveRecord::Base.connection.instance_exec do
  drop_table(:ticks, if_exists: true, force: :cascade)

  hypertable_options = {
    time_column: 'time',
    chunk_time_interval: '1 day',
    compress_segmentby: 'symbol',
    compress_orderby: 'time',
    compress_after: '7 days'
  }

  create_table :ticks, hypertable: hypertable_options, id: false do |t|
    t.timestamp :time
    t.string :symbol
    t.decimal :price
    t.integer :volume
  end
end

FAANG = %w[META AMZN AAPL NFLX GOOG]
OPERATION = [:+, :-]
RAND_VOLUME = -> { (rand(10) * rand(10)) * 100 }
RAND_CENT = -> { (rand / 50.0).round(2) }

def generate_fake_data(total: 100)
  previous_price = {}
  time = Time.now
  (total / FAANG.size).times.flat_map do
    time += rand(10)
    FAANG.map do |symbol|
      if previous_price[symbol]
        price = previous_price[symbol].send(OPERATION.sample, RAND_CENT.()).round(2)
      else
        price = 50 + rand(100)
      end
      payload = { time: time, symbol: symbol, price: price, volume: RAND_VOLUME.() }
      previous_price[symbol] = price
      payload
    end
  end
end

batch = generate_fake_data total: 10_000
ActiveRecord::Base.logger = nil
Tick.insert_all(batch, returning: false)
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Base.connection.instance_exec do
  create_continuous_aggregates('ohlc_1m', Tick.ohlc('1m'), with_data: true)
end

class Ohlc1m < ActiveRecord::Base
  self.table_name = 'ohlc_1m'
  attribute :time, :time
  attribute :symbol, :string
  %w[open high low close volume].each{|name| attribute name, :decimal}

 def readonly?
   true
 end
end

binding.pry
