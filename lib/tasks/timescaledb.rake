# Utility rake task to update the timescaledb extension
# This is necessary to run before running migrations.
# Load this rake task in your Rakefile
#   require 'timescaledb/tasks'

namespace :timescaledb do
  desc "Update TimescaleDB extension (must be run as the first command in a fresh session)"
  task :update_extension => :environment do
    Timescaledb.establish_connection ENV["DATABASE_URL"]
    Timescaledb::Extension.update!
  end
  
  desc "Show TimescaleDB extension version"
  task :version => :environment do
    Timescaledb.establish_connection ENV["DATABASE_URL"]
    puts "TimescaleDB extension version: #{Timescaledb::Extension.version}"
  end
end 
