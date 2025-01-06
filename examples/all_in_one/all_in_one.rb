require 'bundler/inline' #require only what you need

gemfile(true) do 
  gem 'timescaledb', path:  '../..'
  gem 'pry'
  gem 'faker'
end

require 'timescaledb'
require 'pp'
require 'pry'
# ruby all_in_one.rb postgres://user:pass@host:port/db_name
ActiveRecord::Base.establish_connection( ARGV.last)

# Simple example
class Event < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable
end

# Setup Hypertable as in a migration
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  drop_table(:events, if_exists: true, cascade: true)

  hypertable_options = {
    time_column: 'created_at',
    chunk_time_interval: '1 day',
    compress_segmentby: 'identifier',
    compress_after: '7 days'
  }

  create_table(:events, id: false, hypertable: hypertable_options) do |t|
    t.string :identifier, null: false
    t.jsonb :payload
    t.timestamps
  end
end

# Create some data just to see how it works
1.times do
  Event.transaction do
    Event.create identifier: "sign_up", payload: {"name" => "Eon"}
    Event.create identifier: "login", payload: {"email" => "eon@timescale.com"}
    Event.create identifier: "click", payload: {"user" => "eon", "path" => "/install/timescaledb"}
    Event.create identifier: "scroll", payload: {"user" => "eon", "path" => "/install/timescaledb"}
    Event.create identifier: "logout", payload: {"email" => "eon@timescale.com"}
  end
end


def generate_fake_data(total: 100_000)
  time = 1.month.ago
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

def supress_logs
  ActiveRecord::Base.logger =nil
  yield
  ActiveRecord::Base.logger = Logger.new(STDOUT)
end

batch = generate_fake_data total: 10_000
supress_logs do
  Event.insert_all(batch, returning: false)
end
# Now let's see what we have in the scopes
Event.last_hour.group(:identifier).count # => {"login"=>2, "click"=>1, "logout"=>1, "sign_up"=>1, "scroll"=>1}

puts "compressing #{ Event.chunks.count }"
Event.chunks.first.compress!

puts "detailed size"
pp Event.hypertable.detailed_size

puts "compression stats"
pp Event.hypertable.compression_stats

puts "decompressing"
Event.chunks.first.decompress!
Pry.start
