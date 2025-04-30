# This file is used to load the TimescaleDB rake tasks
# When you use `require timescaledb/tasks'` in your Rakefile, this file gets loaded
# and it in turn loads the actual rake tasks from lib/tasks/timescaledb.rake

load File.expand_path('../../tasks/timescaledb.rake', __FILE__) 