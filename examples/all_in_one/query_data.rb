require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb', path:  '../..'
  gem 'pry'
  gem 'faker'
end

require 'pp'
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

# Setup Hypertable as in a migration
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  drop_table(Event.table_name, if_exists: true)

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


batch = generate_fake_data total: 10_000
ActiveRecord::Base.logger = nil
Event.insert_all(batch, returning: false)
ActiveRecord::Base.logger = Logger.new(STDOUT)

pp Event.previous_month.count
pp Event.previous_week.count
pp Event.previous_month.group('identifier').count
pp Event.previous_week.group('identifier').count

pp Event
  .previous_month
  .select("time_bucket('1 day', created_at) as time, identifier, count(*)")
  .group("1,2").map(&:attributes)
