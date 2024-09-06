# TimescaleDB

Welcome to the TimescaleDB gem! To experiment with the code, start installing the
gem:

```bash
gem install timescaledb
```

## The `tsdb` CLI

When you install the gem locally, a new command line application named `tsdb`
will be linked in your command line.

It accepts a Postgresql URI and some extra flags that can help you to get more
info from your TimescaleDB server:

```bash
tsdb <uri> --stats
```

Where the `<uri>` is replaced with params from your connection like:

```bash
tsdb postgres://<user>@localhost:5432/<dbname> --stats
```


Or just check the stats:

```bash
tsdb "postgres://<user>@localhost:5432/timescaledb_test" --stats
```

These is a sample output from database example with almost no data:

```ruby
{:hypertables=>
  {:count=>3,
   :uncompressed=>2,
   :chunks=>{:total=>1, :compressed=>0, :uncompressed=>1},
   :size=>{:before_compressing=>"80 KB", :after_compressing=>"0 Bytes"}},
 :continuous_aggregates=>{:count=>1},
 :jobs_stats=>[{:success=>nil, :runs=>nil, :failures=>nil}]}
```

To start a interactive ruby/[pry](https://github.com/pry/pry) console use `--console`:
The console will dynamically create models for all hypertables that it finds
in the database.

Let's consider the [caggs.sql](https://gist.github.com/jonatas/95573ad8744994094ec9f284150004f9#file-caggs-sql)
as the example of database.


```bash
psql postgres://<user>@localhost:5432/playground -f caggs.sql
```

Then use `tsdb` in the command line with the same URI and `--stats`:

```bash
tsdb postgres://<user>@localhost:5432/playground --stats
{:hypertables=>
  {:count=>1,
   :uncompressed=>1,
   :approximate_row_count=>{"ticks"=>352},
   :chunks=>{:total=>1, :compressed=>0, :uncompressed=>1},
   :size=>{:uncompressed=>"88 KB", :compressed=>"0 Bytes"}},
 :continuous_aggregates=>{:total=>1},
 :jobs_stats=>[{:success=>nil, :runs=>nil, :failures=>nil}]}
```

To have some interactive playground with the actual database using ruby, just
try the same command before changing from `--stats` to `--console`:

### tsdb --console

The same database from previous example, is used so
the context has a hypertable named `ticks` and a view named `ohlc_1m`.


```ruby
tsdb postgres://<user>@localhost:5432/playground --console
pry(Timescale)>
```

The `tsdb` CLI will automatically create ActiveRecord models for hypertables and
continuous aggregates views.

```ruby
Tick
=> Timescaledb::Tick(time: datetime, symbol: string, price: decimal, volume: integer)
```

Note that it's only created for this session and will never be cached in the
library or any other place.

In this case, `Tick` model comes from `ticks` hypertable that was found in the database.
It contains several extra methods inherited from `acts_as_hypertable` macro.

Let's start with the `.hypertable` method.

```ruby
Tick.hypertable
=> #<Timescaledb::Hypertable:0x00007fe99c258900
 hypertable_schema: "public",
 hypertable_name: "ticks",
 owner: "jonatasdp",
 num_dimensions: 1,
 num_chunks: 1,
 compression_enabled: false,
 tablespaces: nil>
```

The core of the hypertables are the fragmentation of the data into chunks that
are the child tables that distribute the data. You can check all chunks directly
from the hypertable relation.

```ruby
Tick.hypertable.chunks
unknown OID 2206: failed to recognize type of 'primary_dimension_type'. It will be treated as String.
=> [#<Timescaledb::Chunk:0x00007fe99c31b068
  hypertable_schema: "public",
  hypertable_name: "ticks",
  chunk_schema: "_timescaledb_internal",
  chunk_name: "_hyper_33_17_chunk",
  primary_dimension: "time",
  primary_dimension_type: "timestamp without time zone",
  range_start: 1999-12-30 00:00:00 +0000,
  range_end: 2000-01-06 00:00:00 +0000,
  range_start_integer: nil,
  range_end_integer: nil,
  is_compressed: false,
  chunk_tablespace: nil,
  data_nodes: nil>]
```

> Chunks are created by partitioning a hypertable's data into one
> (or potentially multiple) dimensions. All hypertables are partitioned by the
> values belonging to a time column, which may be in timestamp, date, or
> various integer forms. If the time partitioning interval is one day,
> for example, then rows with timestamps that belong to the same day are co-located
> within the same chunk, while rows belonging to different days belong to different chunks.
> Learn more [here](https://docs.timescale.com/timescaledb/latest/overview/core-concepts/hypertables-and-chunks/).

Another core concept of TimescaleDB is compression. With data partitioned, it
becomes very convenient to compress and decompress chunks independently.

```ruby
Tick.hypertable.chunks.first.compress!
ActiveRecord::StatementInvalid: PG::FeatureNotSupported: ERROR:  compression not enabled on "ticks"
DETAIL:  It is not possible to compress chunks on a hypertable that does not have compression enabled.
HINT:  Enable compression using ALTER TABLE with the timescaledb.compress option.
```

As compression is not enabled, let's do it executing a plain SQL directly from
the actual context. To borrow a connection, let's use the Tick object.

```ruby
Tick.connection.execute("ALTER TABLE ticks SET (timescaledb.compress)") # => PG_OK
```

And now, it's possible to compress and decompress:

```ruby
Tick.hypertable.chunks.first.compress!
Tick.hypertable.chunks.first.decompress!
```
Learn more about TimescaleDB compression [here](https://docs.timescale.com/timescaledb/latest/overview/core-concepts/compression/).

The `ohlc_1m` view is also available as an ActiveRecord:

```ruby
Ohlc1m
=> Timescaledb::Ohlc1m(bucket: datetime, symbol: string, open: decimal, high: decimal, low: decimal, close: decimal, volume: integer)
```

And you can run any query as you do with regular active record queries.

```ruby
Ohlc1m.order(bucket: :desc).last
=> #<Timescaledb::Ohlc1m:0x00007fe99c2c38e0
 bucket: 2000-01-01 00:00:00 UTC,
 symbol: "SYMBOL",
 open: 0.13e2,
 high: 0.3e2,
 low: 0.1e1,
 close: 0.1e2,
 volume: 27600>
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'timescaledb'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install timescaledb


## Usage

Check the [examples/ranking](examples/ranking) to get a Rails complete example.

You can check the [all_in_one.rb](examples/all_in_one/all_in_one.rb) example that will:

1. Create hypertable with compression settings
2. Insert data
3. Run some queries
4. Check chunk size per model
5. Compress a chunk
6. Check chunk status
7. Decompress a chunk

### Toolkit

Toolkit contains a lot of extra features to analyse data more deeply directly in
the SQL. There are a few examples in the [examples/toolkit-demo](examples/toolkit-demo)
folder that can let you benchmark and see the differences between implementing
the algorithm directly in Ruby or directly in SQL using the [Timescaledb
Toolkit](https://github.com/timescale/timescaledb-toolkit) extension.

For now you can benchmark and compare:

1. [volatility](examples/toolkit-demo/compare_volatility.rb) algorithm.
2. [lttb](examples/toolkit-demo/lttb/lttb_sinatra.rb) algorithm.

### Testing

If you need some inspiration for how are you going to test your hypertables,
please check the [spec/spec_helper.rb](spec/spec_helper.rb) for inspiration.

### Migrations

Create table is now with the `hypertable` keyword allowing to pass a few options
to the function call while also using `create_table` method:

#### create_table with `:hypertable`

```ruby
hypertable_options = {
  time_column: 'created_at',
  chunk_time_interval: '1 min',
  compress_segmentby: 'identifier',
  compression_interval: '7 days'
}

create_table(:events, id: false, hypertable: hypertable_options) do |t|
  t.string :identifier, null: false
  t.jsonb :payload
  t.timestamps
end
```

#### create_continuous_aggregate

This example shows a ticks table grouping ticks as OHLCV histograms for every
minute.

```ruby
hypertable_options = {
  time_column: 'created_at',
  chunk_time_interval: '1 min',
  compress_segmentby: 'symbol',
  compress_orderby: 'created_at',
  compression_interval: '7 days'
}
create_table :ticks, hypertable: hypertable_options, id: false do |t|
  t.string :symbol
  t.decimal :price
  t.integer :volume
  t.timestamps
end
Tick = Class.new(ActiveRecord::Base) do
  self.table_name = 'ticks'
  self.primary_key = 'symbol'
  acts_as_hypertable
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

#### Scenic integration

The [Scenic](https://github.com/scenic-views/scenic) gem is an easy way to
manage database view definitions for a Rails application. TimescaleDB's
continuous aggregates are more complex than regular PostgreSQL views, and
the schema dumper included with Scenic can't dump a complete definition.

This gem automatically configures Scenic to use a `Timescaledb::Scenic::Adapter`
which will correctly handle schema dumping.

### Enable ActsAsHypertable

Create your `config/initializers/timescaledb.rb` file and add the following line:

```ruby
ActiveRecord::Base.extend Timescaledb::ActsAsHypertable
```

You can declare a Rails model as a Hypertable by invoking the `acts_as_hypertable` macro. This macro extends your existing model with timescaledb-related functionality.
model:

```ruby
class Event < ActiveRecord::Base
  acts_as_hypertable
end
```

By default, ActsAsHypertable assumes a record's _time_column_ is called `created_at`.

You may isolate your hypertables in another database, so, creating an abstract
layer for your hypertables is a good idea:

```ruby
class Hypertable < ActiveRecord::Base
  self.abstract_class = true

  extend Timescaledb::ActsAsHypertable

  establish_connection :timescaledb
end
```

And then, you can inherit from this model:

```ruby
class Event < Hypertable
  acts_as_hypertable time_column: "time"
end
```

Or you can include only when you're going to use them:

```ruby
class Event < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable

  establish_connection :timescaledb

  acts_as_hypertable time_column: "time"
end
```

### Options

If you are using a different time_column name, you can specify it as follows when invoking the `acts_as_hypertable` macro:

```ruby
class Event < ActiveRecord::Base
  acts_as_hypertable time_column: :timestamp
end
```

### Chunks

To get all the chunks from a model's hypertable, you can use `.chunks`.

```ruby
Event.chunks # => [#<Timescaledb::Chunk>, ...]
```

### Hypertable metadata

To get the models' hypertable metadata, you can use `.hypertable`.

```ruby
Event.hypertable # => #<Timescaledb::Hypertable>
```

To get hypertable metadata for all hypertables: `Timescaledb.hypertables`.

### Compression Settings

Compression settings are accessible through the hypertable.

```ruby
Event.hypertable.compression_settings # => [#<Timescaledb::CompressionSettings>, ...]
```

To get compression settings for all hypertables: `Timescaledb.compression_settings`.

### Skip association scopes

If you don't want to overload your model, you can skip the `.hypertable` and other association scopes by passing `skip_association_scopes: true` to the `acts_as_hypertable` macro.

```ruby
class Event < ActiveRecord::Base
  acts_as_hypertable time_column: "time", skip_association_scopes: true
end
```

### Scopes

The `acts_as_hypertable` macro can be very useful to generate some extra scopes
for you. Example of a weather condition:

```ruby
class Condition < ActiveRecord::Base
  acts_as_hypertable time_column: "time"
end
```

Through the [ActsAsHypertable](./lib/timescaledb/acts_as_hypertable) on the model,
a few scopes are created based on the `time_column` argument:

| Scope name             | What they return                      |
|------------------------|---------------------------------------|
| `Model.previous_month` | Records created in the previous month |
| `Model.previous_week`  | Records created in the previous week  |
| `Model.this_month`     | Records created this month            |
| `Model.this_week`      | Records created this week             |
| `Model.yesterday`      | Records created yesterday             |
| `Model.today`          | Records created today                 |
| `Model.last_hour`      | Records created in the last hour      |

All time-related scopes respect your application's timezone.

When you enable ActsAsTimeVector on your model, we include a couple default scopes. They are:

```ruby
class Condition < ActiveRecord::Base
  acts_as_time_vector time_column: "time",
    value_column: "temperature",
    segment_by: "device_id"
end
```

### Skip default scopes

You can skip the default scopes by passing `skip_default_scopes: true` to the `acts_as_hypertable` macro.

```ruby
class Condition < ActiveRecord::Base
  acts_as_hypertable time_column: "time", skip_default_scopes: true
end
```

## RSpec Hooks

In case you want to use TimescaleDB on a Rails environment, you may have some
issues as the schema dump used for tests does not consider hypertables metadata.

As a work around, you can dynamically create the hypertables yourself for
testing environments using the following hook which you can
define in `spec/rspec_helper.rb`:

```ruby
config.before(:suite) do

  hypertable_models = ActiveRecord::Base.descendants.select(&:acts_as_hypertable?)

  hypertable_models.each do |klass|
    table_name = klass.table_name
    time_column = klass.hypertable_options[:time_column]

    if klass.try(:hypertable).present?
      ApplicationRecord.logger.info "hypertable already created for '#{table_name}', skipping."
      next
    end

    ApplicationRecord.connection.execute <<~SQL
      SELECT create_hypertable('#{table_name}', '#{time_column.to_s}')
    SQL
  end
end
```

## Schema Dumper

If you're using the gem with Rails and you want to dump the schema to a file,
The schema dumper will include:

* hypertables configuration
* compression settings
* continuous aggregates (also integrated with Scenic gem)
* compression and retention policies

The idea is try to mimic the last state of art of the database.
The schema dumper will also ignore the `Timescaledb::SchemaDumper::IGNORE_SCHEMAS`
that is an array of schema names that you want to ignore. By default it ignores
all catalog and metadata generated by the extension, but keep in mind you can
change this behavior.

```ruby
Timescaledb::SchemaDumper::IGNORE_SCHEMAS << "ignore_my_schema_too"
```

## Development

After checking out the repo, run `bin/setup` to install the development dependencies. Then, `bundle exec rake test:setup` to setup the test database and tables. Finally, run `bundle exec rake` to run the tests.

You can also run `tsdb` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

You can create a `.env` file locally to run tests locally. Make sure to put your
own credentials there!

```bash
PG_URI_TEST="postgres://<user>@localhost:5432/<dbname>"
```

You can put some postgres URI directly as a parameter of
`tsdb`. Here is an example from the console:

```bash
tsdb "postgres://<user>@localhost:5432/timescaledb_test"
```

## More resources

This library was started on [twitch.tv/timescaledb](https://twitch.tv/timescaledb).
You can watch all episodes here:

1. [Wrapping Functions to Ruby Helpers](https://www.youtube.com/watch?v=hGPsUxLFAYk).
2. [Extending ActiveRecord with Timescale Helpers](https://www.youtube.com/watch?v=IEyJIHk1Clk).
3. [Setup Hypertables for Rails testing environment](https://www.youtube.com/watch?v=wM6hVrZe7xA).
4. [Packing the code to this repository](https://www.youtube.com/watch?v=CMdGAl_XlL4).
4. [the code to this repository](https://www.youtube.com/watch?v=CMdGAl_XlL4).
5. [Working with Timescale continuous aggregates](https://youtu.be/co4HnBkHzVw).
6. [Creating the command-line application in Ruby to explore the Timescale API](https://www.youtube.com/watch?v=I3vM_q2m7T0).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/timescaledb. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jonatas/timescaledb/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jonatas/timescaledb/blob/master/CODE_OF_CONDUCT.md).
