require 'bundler/inline' #require only what you need

gemfile(true) do 
  gem 'timescaledb', path:  '../..'
  gem 'pry'
  gem 'faker'
  gem 'benchmark-ips', require: "benchmark/ips", git: 'https://github.com/evanphx/benchmark-ips'
end

require 'pp'
require 'benchmark'
# ruby all_in_one.rb postgres://user:pass@host:port/db_name
ActiveRecord::Base.establish_connection( ARGV.last)

# Simple example
class Event < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable

# If you want to override the automatic assingment of the `created_at ` time series column
  def self.timestamp_attributes_for_create_in_model
    []
  end
  def self.timestamp_attributes_for_update_in_model
    []
  end
end

class Event2 < ActiveRecord::Base
  self.table_name = "events_2"
end

# Setup Hypertable as in a migration
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  drop_table(Event.table_name, if_exists: true)
  drop_table(Event2.table_name, if_exists: true)

  hypertable_options = {
    time_column: 'created_at',
    chunk_time_interval: '7 day',
    compress_segmentby: 'identifier',
    compress_after: '7 days'
  }

  create_table(:events, id: false, hypertable: hypertable_options) do |t|
    t.string :identifier, null: false
    t.jsonb :payload
    t.timestamps
  end

  create_table(Event2.table_name) do |t|
    t.string :identifier, null: false
    t.jsonb :payload
    t.timestamps
  end
end

def generate_fake_data(total: 100_000)
  time = Time.now
  total.times.flat_map do
    identifier = %w[sign_up login click scroll logout view]
    time = time + rand(60).seconds
    {
      created_at: time,
      updated_at: time,
      identifier: identifier.sample,
      payload: {
        "name" => Faker::Name.name,
        "email" => Faker::Internet.email
      }
    }
  end
end


def parallel_inserts clazz: nil, size: 5_000, data: nil
  limit = 8
  threads = []
  while (batch = data.shift(size)).any? do
    threads << Thread.new(batch) do |batch|
      begin
        clazz.insert_all(batch, returning: false)
      ensure
        ActiveRecord::Base.connection.close if ActiveRecord::Base.connection
      end
    end
    if threads.size == limit
      threads.each(&:join)
      threads = []
    end
  end
  threads.each(&:join)
end

payloads = nil
ActiveRecord::Base.logger = nil
Benchmark.ips do |x|
  x.config(time: 500, warmup: 2)

  x.report("gen data") { payloads = generate_fake_data total: 100_000}
  x.report("normal  ") { parallel_inserts(data: payloads.dup, clazz: Event2, size: 5000)  }
  x.report("hyper   ") { parallel_inserts(data: payloads.dup, clazz: Event, size: 5000)  }
  x.compare!
end
ActiveRecord::Base.logger = Logger.new(STDOUT)

