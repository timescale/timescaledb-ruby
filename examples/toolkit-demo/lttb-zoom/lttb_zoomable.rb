# ruby lttb_zoomable.rb postgres://user:pass@host:port/db_name
require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb', path:  '../../..'
  gem 'pry'
  gem 'sinatra', require: false
  gem 'sinatra-reloader'
  gem 'sinatra-cross_origin'
  gem 'puma'
end

require 'timescaledb/toolkit'
require 'sinatra'
require 'sinatra/json'
require 'sinatra/contrib'

register Sinatra::Reloader
register Sinatra::Contrib

PG_URI = ARGV.last

VALID_SIZES = %i[small med big]
def download_weather_dataset size: :small
  unless VALID_SIZES.include?(size)
    fail "Invalid size: #{size}. Valids are #{VALID_SIZES}"
  end
  url = "https://assets.timescale.com/docs/downloads/weather_#{size}.tar.gz"
  puts "fetching #{size} weather dataset..."
  system "wget \"#{url}\""
  puts "done!"
end

def setup size: :small
  file = "weather_#{size}.tar.gz"
  download_weather_dataset(size: size) unless File.exists? file
  puts "extracting #{file}"
  system "tar -xvzf #{file} "
  puts "creating data structures"
  system "psql #{PG_URI} < weather.sql"
  system %|psql #{PG_URI} -c "\\COPY conditions FROM weather_#{size}_conditions.csv CSV"|
  system %|psql #{PG_URI} -c "\\COPY locations FROM weather_#{size}_locations.csv CSV"|
end

ActiveRecord::Base.establish_connection(PG_URI)

class Condition < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  extend Timescaledb::ActsAsTimeVector

  acts_as_hypertable time_column: "time"
  acts_as_time_vector value_column: "temperature", segment_by: "device_id"
end

# Setup Hypertable as in a migration
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  if !Condition.table_exists?  || Condition.count.zero?

    setup size: :big
    binding.pry
  end
end


def filter_by_request_params
  filter= {device_id: "weather-pro-000001"}
  if params[:filter] && params[:filter] != "null"
    from, to = params[:filter].split(",").map(&Time.method(:parse))
    filter[:time] = from..to
  end
  filter
end

def conditions
  Condition.where(filter_by_request_params).order('time')
end

def threshold
  params[:threshold]&.to_i || 50
end

configure do
  enable :cross_origin
end

get '/' do
  erb :index
end

get "/lttb_sql" do
  downsampled = conditions.lttb(threshold: threshold, segment_by: nil)
  json downsampled
end
