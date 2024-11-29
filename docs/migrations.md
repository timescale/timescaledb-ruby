# ActiveRecord migrations helpers for Timescale

Create table is now with the `hypertable` keyword allowing to pass a few options
to the function call while also using the `create_table` method:

## create_table with the `:hypertable` option

```ruby
hypertable_options = {
  time_column: 'created_at',
  chunk_time_interval: '1 min',
  compress_segmentby: 'identifier',
  compress_after: '7 days'
}

create_table(:events, id: false, hypertable: hypertable_options) do |t|
  t.datetime :created_at, null: false
  t.string :identifier, null: false
  t.jsonb :payload
end
```

## The `create_continuous_aggregate` helper

This goes in the model file.  This example shows a ticks table grouping ticks as OHLCV histograms for every
minute.

First make sure you have the model with the `acts_as_hypertable` method to be
able to extract the query from it.

```ruby
class Tick < ActiveRecord::Base
  self.table_name = 'ticks'
  acts_as_hypertable
end
```

Then, inside your migration:

```ruby
hypertable_options = {
  time_column: 'created_at',
  chunk_time_interval: '1 min',
  compress_segmentby: 'symbol',
  compress_orderby: 'created_at',
  compress_after: '7 days'
}
create_table :ticks, hypertable: hypertable_options, id: false do |t|
  t.string :symbol
  t.decimal :price
  t.integer :volume
  t.timestamps
end

query = Tick.select(<<~QUERY)
  time_bucket('1m', created_at) as time,
  symbol,
  FIRST(price, created_at) as open,
  MAX(price) as high,
  MIN(price) as low,
  LAST(price, created_at) as close,
  SUM(volume) as volume").group("1,2")
QUERY

options = {
  with_data: false,
  refresh_policies: {
    start_offset: "INTERVAL '1 month'",
    end_offset: "INTERVAL '1 minute'",
    schedule_interval: "INTERVAL '1 minute'"
  }
}

create_continuous_aggregate('ohlc_1m', query, **options)
```

If you need more details, please check this [blog post][1].

If you're interested in candlesticks and need to get the OHLC values, take a look
at the [toolkit ohlc](/toolkit_ohlc) function that do the same but through a
function that can be reusing candlesticks from smaller timeframes.

!!! note "Disable ddl transactions in your migration to start with data"

    If you want to start `with_data: true`, remember that you'll need to
    `disable_ddl_transaction!` in your migration file.

    ```ruby
    class CreateCaggsWithData < ActiveRecord::Migration[7.0]
      disable_ddl_transaction!

      def change
        create_continuous_aggregate('ohlc_1m', query, with_data: true)
        # ...
      end
    end
    ```

# Create a continuous aggregate using the macro

To setup complex [hierarchies][hierarchical] of continuous aggregates, you can use the `continuous_aggregates` macro.

This setup allows for creating multiple continuous aggregates with customizable refresh policies, making it ideal for complex aggregation and retention policies. 

```ruby
class Download < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  include Timescaledb::ContinuousAggregatesHelper

  acts_as_hypertable time_column: 'ts'

  scope :total_downloads, -> { select("count(*) as total") }
  scope :downloads_by_gem, -> { select("gem_name, count(*) as total").group(:gem_name) }
  scope :downloads_by_version, -> { select("gem_name, gem_version, count(*) as total").group(:gem_name, :gem_version) }

  continuous_aggregates(
    timeframes: [:minute, :hour, :day, :month],
    scopes: [:total_downloads, :downloads_by_gem, :downloads_by_version],
    refresh_policy: {
      minute: { start_offset: "10 minutes", end_offset: "1 minute", schedule_interval: "1 minute" },
      hour:   { start_offset: "4 hour",     end_offset: "1 hour",   schedule_interval: "1 hour" },
      day:    { start_offset: "3 day",      end_offset: "1 day",    schedule_interval: "1 day" },
      month:  { start_offset: "3 month",    end_offset: "1 day",  schedule_interval: "1 day" }
  })
end
```

Then edit the migration file to add the continuous aggregates:

```ruby
class CreateCaggs < ActiveRecord::Migration[7.0]
  def up
    Download.create_continuous_aggregates
  end

  def down
    Download.drop_continuous_aggregates
  end
end
```

Here is the output of the migration:

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS total_downloads_per_minute
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 minute', ts) as ts, count(*) as total FROM "downloads" GROUP BY 1
WITH NO DATA;

SELECT add_continuous_aggregate_policy('total_downloads_per_minute',
  start_offset => INTERVAL '10 minutes',
  end_offset =>  INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');

CREATE MATERIALIZED VIEW IF NOT EXISTS total_downloads_per_hour
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) as ts, sum(total) as total FROM "total_downloads_per_minute" GROUP BY 1
WITH NO DATA;

SELECT add_continuous_aggregate_policy('total_downloads_per_hour',
  start_offset => INTERVAL '4 hour',
  end_offset =>  INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');

CREATE MATERIALIZED VIEW IF NOT EXISTS total_downloads_per_day
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', ts) as ts, sum(total) as total FROM "total_downloads_per_hour" GROUP BY 1
WITH NO DATA;

SELECT add_continuous_aggregate_policy('total_downloads_per_day',
  start_offset => INTERVAL '3 day',
  end_offset =>  INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');

CREATE MATERIALIZED VIEW IF NOT EXISTS total_downloads_per_month
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 month', ts) as ts, sum(total) as total FROM "total_downloads_per_day" GROUP BY 1
WITH NO DATA;

SELECT add_continuous_aggregate_policy('total_downloads_per_month',
  start_offset => INTERVAL '3 month',
  end_offset =>  INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_gem_per_minute
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 minute', ts) as ts, gem_name, count(*) as total FROM "downloads" GROUP BY 1, "downloads"."gem_name"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_gem_per_minute',
  start_offset => INTERVAL '10 minutes',
  end_offset =>  INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_gem_per_hour
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) as ts, gem_name, sum(total) as total FROM "downloads_by_gem_per_minute" GROUP BY 1, "downloads_by_gem_per_minute"."gem_name"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_gem_per_hour',
  start_offset => INTERVAL '4 hour',
  end_offset =>  INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_gem_per_day
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', ts) as ts, gem_name, sum(total) as total FROM "downloads_by_gem_per_hour" GROUP BY 1, "downloads_by_gem_per_hour"."gem_name"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_gem_per_day',
  start_offset => INTERVAL '3 day',
  end_offset =>  INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_gem_per_month
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 month', ts) as ts, gem_name, sum(total) as total FROM "downloads_by_gem_per_day" GROUP BY 1, "downloads_by_gem_per_day"."gem_name"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_gem_per_month',
  start_offset => INTERVAL '3 month',
  end_offset =>  INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_version_per_minute
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 minute', ts) as ts, gem_name, gem_version, count(*) as total FROM "downloads" GROUP BY 1, "downloads"."gem_name", "downloads"."gem_version"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_version_per_minute',
  start_offset => INTERVAL '10 minutes',
  end_offset =>  INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_version_per_hour
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) as ts, gem_name, gem_version, sum(total) as total FROM "downloads_by_version_per_minute" GROUP BY 1, "downloads_by_version_per_minute"."gem_name", "downloads_by_version_per_minute"."gem_version"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_version_per_hour',
  start_offset => INTERVAL '4 hour',
  end_offset =>  INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_version_per_day
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', ts) as ts, gem_name, gem_version, sum(total) as total FROM "downloads_by_version_per_hour" GROUP BY 1, "downloads_by_version_per_hour"."gem_name", "downloads_by_version_per_hour"."gem_version"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_version_per_day',
  start_offset => INTERVAL '3 day',
  end_offset =>  INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');

CREATE MATERIALIZED VIEW IF NOT EXISTS downloads_by_version_per_month
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 month', ts) as ts, gem_name, gem_version, sum(total) as total FROM "downloads_by_version_per_day" GROUP BY 1, "downloads_by_version_per_day"."gem_name", "downloads_by_version_per_day"."gem_version"
WITH NO DATA;

SELECT add_continuous_aggregate_policy('downloads_by_version_per_month',
  start_offset => INTERVAL '3 month',
  end_offset =>  INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');
```

When `drop_continuous_aggregates` is called, it considers the reverse order of creation.

```sql
DROP MATERIALIZED VIEW IF EXISTS total_downloads_per_month CASCADE
DROP MATERIALIZED VIEW IF EXISTS total_downloads_per_day CASCADE
DROP MATERIALIZED VIEW IF EXISTS total_downloads_per_hour CASCADE
DROP MATERIALIZED VIEW IF EXISTS total_downloads_per_minute CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_gem_per_month CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_gem_per_day CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_gem_per_hour CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_gem_per_minute CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_version_per_month CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_version_per_day CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_version_per_hour CASCADE
DROP MATERIALIZED VIEW IF EXISTS downloads_by_version_per_minute CASCADE
```


The convention of naming the scopes is important as they mix with the name of the continuous aggregate.


[1]: https://ideia.me/timescale-continuous-aggregates-with-ruby
[hierarchical]: https://docs.timescale.com/use-timescale/latest/continuous-aggregates/hierarchical-continuous-aggregates/
