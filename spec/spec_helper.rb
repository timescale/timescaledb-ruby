require "bundler/setup"
require "pry"
require "rspec/its"
require "timescaledb"
require 'timescaledb/toolkit'
require "dotenv"
require "database_cleaner/active_record"
require_relative "support/active_record/models"
require_relative "support/active_record/schema"

ENV['PG_URI_TEST'] || Dotenv.load!

ActiveRecord::Base.establish_connection(ENV['PG_URI_TEST'])
Timescaledb.establish_connection(ENV['PG_URI_TEST'])

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

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do |example|
    DatabaseCleaner.strategy = example.metadata.fetch(:database_cleaner_strategy, :transaction)
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
