require "bundler/setup"
require "pry"
require "rspec/its"
require "timescaledb"
require 'timescaledb/toolkit'
require "dotenv"
require "database_cleaner/active_record"
require "active_support/testing/time_helpers"

Dotenv.load! if File.exist?(".env")

ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end

ActiveRecord::Base.establish_connection(ENV['PG_URI_TEST'])
Timescaledb.establish_connection(ENV['PG_URI_TEST'])

require_relative "support/active_record/models"
require_relative "support/active_record/schema"

def destroy_all_chunks_for!(klass)
  sql = <<-SQL
    SELECT drop_chunks('#{klass.table_name}', '#{1.week.from_now}'::date)
  SQL

  ActiveRecord::Base.connection.execute(sql)
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.before(:suite) do
    Time.zone = 'UTC'
  end
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do |example|
    DatabaseCleaner.strategy = example.metadata.fetch(:database_cleaner_strategy, :transaction)
    DatabaseCleaner.start
  end

  config.after(:each) do
    retries = 3
    begin
      DatabaseCleaner.clean
    rescue ActiveRecord::StatementInvalid => e
      if e.message =~ /deadlock detected/ && (retries -= 1) > 0
        sleep 0.1
        retry
      else
        raise
      end
    end
  end

  config.include ActiveSupport::Testing::TimeHelpers
end
