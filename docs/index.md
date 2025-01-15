# TimescaleDB Ruby Gem

> The Timescale SDK for Ruby

A Ruby [gem](https://rubygems.org/gems/timescaledb) for working with TimescaleDB - an open-source time-series database built on PostgreSQL. This gem provides ActiveRecord integration and helpful tools for managing time-series data.

## What is TimescaleDB?

TimescaleDB extends PostgreSQL with specialized features for time-series data:

- **Hypertables**: Automatically partitioned tables optimized for time-series data
- **Hypercores**: Hypercore is a dynamic storage engine that allows you to store data in a way that is optimized for time-series data
- **Chunks**: Transparent table partitions that improve query performance
- **Continuous Aggregates**: Materialized views that automatically update
- **Data Compression**: Automatic compression of older data
- **Data Retention**: Policies for managing data lifecycle

## Installation

Add to your Gemfile:

```ruby
gem 'timescaledb'
```

Or install directly:

```bash
gem install timescaledb
```

## Quick Start

### 1. Create Hypertables in Migrations

```ruby
class CreateEvents < ActiveRecord::Migration[7.0]
  def up
    hypertable_options = {
      time_column: 'created_at',
      chunk_time_interval: '1 day',
      compress_segmentby: 'identifier',
      compress_orderby: 'created_at DESC',
      compress_after: '7 days',
      drop_after: '3 months',
      partition_column: 'user_id',        # Optional: Add space partitioning
      number_partitions: 4                # Required when using partition_column 
    }

    create_table(:events, id: false, hypertable: hypertable_options) do |t|
      t.timestamptz :created_at
      t.string :identifier, null: false
      t.jsonb :payload
      t.integer :user_id
    end
  end
end
```

### 2. Enable TimescaleDB in Your Models

#### Global Configuration

```ruby
# config/initializers/timescaledb.rb
ActiveSupport.on_load(:active_record) { extend Timescaledb::ActsAsHypertable }

# app/models/event.rb
class Event < ActiveRecord::Base
  acts_as_hypertable time_column: "time",
    segment_by: "identifier",
    value_column: "cast(payload->>'value' as float)"
end
```

#### Per-Model Configuration

```ruby
class Event < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  acts_as_hypertable time_column: "time"
end
```

#### Abstract Model Configuration

```ruby
class Hypertable < ActiveRecord::Base
  self.abstract_class = true
  extend Timescaledb::ActsAsHypertable
end

class Event < Hypertable
  acts_as_hypertable time_column: "time"
end
```

## Advanced Features

We're always looking for ways to improve the gem and make it easier to use. Feel free to open an issue or a PR if you have any ideas or suggestions.

### Scenic Integration

The gem integrates with the Scenic gem for managing database views:

```ruby
class CreateAnalyticsView < ActiveRecord::Migration[7.0]
  def change
    create_view :daily_analytics, 
      materialized: true, 
      version: 1,
      with: "timescaledb.continuous"
  end
end
```

### Compression Settings

Access and configure compression settings:

```ruby
# Check compression settings
Event.hypertable.compression_settings

# Get compression stats
Event.hypertable.compression_stats

# Compress specific chunks
Event.chunks.uncompressed.where("end_time < ?", 1.week.ago).each(&:compress!)
```

### Job Management

Monitor and manage background jobs:

```ruby
# List all jobs
Timescaledb::Job.all

# Check compression jobs
Timescaledb::Job.compression.scheduled

# View job statistics
Timescaledb::JobStats.success.resume
```

### Dimensions and Partitioning

Access information about table dimensions:

```ruby
# Get main time dimension
Event.hypertable.main_dimension

# Check all dimensions
Event.hypertable.dimensions
```

### Extension Management

Manage the TimescaleDB extension:

```ruby
# Check version
Timescaledb::Extension.version

# Check if installed
Timescaledb::Extension.installed?

# Update extension
Timescaledb::Extension.update!
```

## Schema Dumper

The gem enhances Rails' schema dumper to handle TimescaleDB-specific features:

- Hypertable configurations
- Compression settings
- Continuous aggregates
- Retention policies
- Space partitioning

## Continuous Aggregates Macro

The gem provides a macro for creating continuous aggregates:

```ruby
class Achievement < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  acts_as_hypertable time_column: "time", segment_by: "user_id", value_column: "points"

  scope :count_by_user, -> { group(:user_id).count }
  scope :points_by_user, -> { group(:user_id).sum(:points) }

  continuous_aggregate scopes: [:count_by_user, :points_by_user],
    timeframes: [:hour, :day, :month]
end
```
Then in your migrations:

```ruby
class CreateAchievements < ActiveRecord::Migration[7.0]
  def up
    hypertable = {
      time_column: "created_at",
      segment_by: "user_id",
      value_column: "points"
    }

    create_table :achievements, id: false, hypertable: hypertable do |t|
      t.timestamptz :created_at, default: -> { "now()" }
      t.integer :user_id, null: false
      t.integer :points, null: false, default: 1
    end
    Achievement.create_continuous_aggregate
  end

  def down
    Achievement.drop_continuous_aggregate
    drop_table :achievements
  end
end
```

Check the blog post for more details: [building a better Ruby ORM for time series data](https://www.timescale.com/blog/building-a-better-ruby-orm-for-time-series-and-analytics).

## Testing Support

For testing environments, you can use this RSpec configuration:

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.before(:suite) do
    hypertable_models = ActiveRecord::Base.descendants.select(&:acts_as_hypertable?)
    
    hypertable_models.each do |klass|
      next if klass.try(:hypertable).present?
      
      ApplicationRecord.connection.create_hypertable(
        klass.table_name,
        time_column: klass.hypertable_options[:time_column],
        chunk_time_interval: '1 day'
      )
    end
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/timescale/timescaledb-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/timescale/timescaledb-ruby/blob/master/CODE_OF_CONDUCT.md).

You can also connect to the #ruby channel on the [TimescaleDB Community Slack](https://slack.timescale.com).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/timescale/timescaledb-ruby/blob/master/CODE_OF_CONDUCT.md).
