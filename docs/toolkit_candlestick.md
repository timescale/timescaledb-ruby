  # Candlesticks

Candlesticks are a popular tool in technical analysis, used by traders to determine potential market movements. The [toolkit][toolkit] allows you to compute candlesticks with the [candlestick][candlestick] function.

Let's start by defining a table that stores trades from financial market data, and then we can calculate the candlesticks with the Timescaledb Toolkit.

## Setting up the environment

First, we'll set up our environment with the necessary gems:

```ruby
require 'bundler/inline'

gemfile(true) do
  gem 'timescaledb', path: '../..'
  gem 'pry'
  gem 'puma'
  gem 'sinatra'
  gem 'sinatra-contrib'
  gem 'sinatra-reloader'
end

ActiveRecord::Base.establish_connection ARGV.first
```

## Creating the hypertable

We'll create a hypertable called `ticks` to store the market data:

```ruby
def db(&block)
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.connection.instance_exec(&block)
  ActiveRecord::Base.logger = nil
end

db do
  drop_table :ticks, if_exists: true, force: :cascade

  hypertable_options = {
    time_column: "time",
    chunk_time_interval: "1 day",
    compress_segmentby: "symbol",
    compress_orderby: "time",
    compression_interval: "1 month"
  }
  create_table :ticks, hypertable: hypertable_options, id: false do |t|
    t.timestamp :time
    t.string :symbol
    t.decimal :price
    t.decimal :volume
  end

  add_index :ticks, [:time, :symbol]
end
```

## Creating the ORM model

To define the model, we'll inherit `ActiveRecord::Base` to create a model. Timeseries data will always require the time column, and the primary key can be discarded. A few default methods will not work if they depend on the id of the object.

The model is the best place to describe how you'll be using the timescaledb to keep your model DRY and consistent.

```ruby
class Tick < ActiveRecord::Base
  acts_as_hypertable time_column: :time
  acts_as_time_vector value_column: :price, segment_by: :symbol

   scope :ohlcv, -> do
    select("symbol,
            first(price, time) as open,
            max(price) as high,
            min(price) as low,
            last(price, time) as close,
            sum(volume) as volume").group("symbol")
  end
  scope :plotly_candlestick, -> (from: nil) do
    data = all.to_a
    {
      type: 'candlestick',
      xaxis: 'x',
      yaxis: 'y',
      x: data.map(&:time),
      open: data.map(&:open),
      high: data.map(&:high),
      low: data.map(&:low),
      close: data.map(&:close),
      volume: data.map(&:volume)
    }
  end

  continuous_aggregates(
    timeframes: [:minute, :hour, :day, :month],
    scopes: [:ohlcv],
    refresh_policy: {
      minute: { start_offset: "10 minutes", end_offset: "1 minute", schedule_interval: "1 minute" },
      hour:   { start_offset: "4 hour",     end_offset: "1 hour",   schedule_interval: "1 hour" },
      day:    { start_offset: "3 day",      end_offset: "1 day",    schedule_interval: "1 day" },
      month:  { start_offset: "3 month",    end_offset: "1 day",  schedule_interval: "1 day" }
  })

  descendants.each{|e|e.time_vector_options = time_vector_options.merge(value_column: :close)}
end
```

The `acts_as_hypertable` macro will assume the actual model corresponds to a hypertable and inject useful scopes and methods that can be wrapped to the following TimescaleDB features:

* `.hypertable` will give you access to the [hypertable][hypertable] domain, the `table_name` will be used to get all metadata from the `_timescaledb_catalog` and combine all the functions that receives a hypertable_name as a parameter.
* The `time_column` keyword argument will be used to build scopes like `.yesterday`, `.previous_week`, `.last_hour`. And can be used for your own scopes using the `time_column` metadata.

The `acts_as_time_vector` will be offering functions related to timescaledb toolkit.

The `value_column:` will be combined with the `time_column` from the hypertable to use scopes like `candlestick`, `volatility`, `lttb` and just configure the missing information.

The `segment_by:` will be widely used in the scopes to group by the data.

When the keywords `time_column`, `value_column` and `segment_by` are used in the `acts_as_{hypertable,time_vector}` modules.

By convention, all scopes reuse the metadata from the configuration. It can facilitate the process of building a lot of hypertable abstractions to facilitate the use combined scopes in the queries.

### The `acts_as_hypertable` macro

The `acts_as_hypertable` will bring the `Model.hypertable` which will allow us to use a set of timeseries related set what are the default columns used to calculate the data.

### The `acts_as_time_vector` macro

The `acts_as_time_vector` will allow us to set what are the default columns used to calculate the data. It can be very handy to avoid repeating the same arguments in all the scopes.

It will be very powerful to build your set of abstractions over it and simplify the maintenance of complex queries directly in the database.

### The `continuous_aggregates` macro

The `continuous_aggregates` macro will allow us to create continuous aggregates for the model. Generating a new materialized view for each scope + timeframe that will be continuously aggregated from the raw data.

The views will be rolling out from previous time frames, so it will be very efficient in terms of resource usage.

## Inserting data

The `generate_series` sql function can speed up the process to seed some random data and make it available to start playing with the queries.

The following code will insert tick data simulating prices from the previous week until yesterday. We're using a single symbol and one tick every 10 seconds.

```ruby
ActiveRecord::Base.connection.instance_exec do
  data_range = {from: 1.week.ago.to_date, to: 1.day.from_now.to_date}
  execute(ActiveRecord::Base.sanitize_sql_for_conditions( [<<~SQL, data_range]))
    INSERT INTO ticks
    SELECT time, 'SYMBOL', 1 + (random()*30)::int, 100*(random()*10)::int
    FROM generate_series(
      TIMESTAMP :from,
      TIMESTAMP :to,
      INTERVAL '10 second') AS time;
    SQL
end
```

The database will seed a week of trade data with a randomize prices and volumes simulating one event every 10 seconds.

The candlestick will split the timeframe by the `time_column` and use the `price` as the default value to process the candlestick. It will also segment the candles by the `symbol`. Symbol can be any stock trade and it's good to be segmenting and indexing by it.

If you need to generate some data for your table, please check [this post][2].

## Query data

When the `acts_as_time_vector` method is used in the model, it will inject several scopes from the toolkit to easily have access to functions like the `_candlestick`.

The `candlestick` scope is available with a few parameters that inherits the configuration from the `acts_as_time_vector` declared previously.

The simplest query is:

```ruby
Tick.candlestick(timeframe: '1m')
```

It will generate the following SQL:

```sql
 SELECT symbol,
    "time",
    open(candlestick),
    high(candlestick),
    low(candlestick),
    close(candlestick),
    open_time(candlestick),
    high_time(candlestick),
    low_time(candlestick),
    close_time(candlestick),
    volume(candlestick),
    vwap(candlestick)
FROM (
    SELECT time_bucket('1m', time) as time,
      "ticks"."symbol",
      candlestick_agg(time, price, volume) as candlestick
    FROM "ticks" GROUP BY 1, 2 ORDER BY 1)
AS candlestick
```

The timeframe argument can also be skipped and the default is `1 hour`.

You can also combine other scopes to filter data before you get the data from the candlestick:

```ruby
Tick.yesterday
  .where(symbol: "APPL")
  .candlestick(timeframe: '1m')
```

The `yesterday` scope is automatically included because of the `acts_as_hypertable` macro. And it will be combining with other where clauses.

## Continuous aggregates

If you would like to create the continuous process one by one in the stream and aggregate the candlesticks on a materialized view you can use continuous aggregates for it.

The next examples shows how to create a single continuous aggregates of 1 minute candlesticks:

```ruby
ActiveRecord::Base.connection.instance_exec do
  options = {
    with_data: true,
    refresh_policies: {
      start_offset: "INTERVAL '1 month'",
      end_offset: "INTERVAL '1 minute'",
      schedule_interval: "INTERVAL '1 minute'"
    }
  }
  create_continuous_aggregate('candlestick_1m', Tick._candlestick(timeframe: '1m'), **options)
end
```

Note that the `create_continuous_aggregate` calls the `to_sql` method in case the second parameter is not a string.

Also, we're using the `_candlestick` method scope instead of the `candlestick` one.

The reason is that the `candlestick` method already bring the attribute values while the `_candlestick` can bring you the pre-processed data in a intermediate state that can be rolled up with other candlesticks. For example, let's say you already created a continuous aggregates of one minute and now you'd like to process 5 minutes. You don't need to reprocess the raw data. You can build the candlestick using the information from the one minute candlesticks.

## Models for views

The macro `continuous_aggregates` will create a new model for each continuous aggregate.

It's very convenient to setup models for continuous aggregates which can make it easy to inherit all smart methods to compose queries.

```ruby
Tick::CandlestickPerMinute
Tick::CandlestickPerHour
Tick::CandlestickPerDay
Tick::CandlestickPerMonth
```

## Hierarchical continuous aggregates

After you get the first one minute continuous aggregates, you don't need to revisit the raw data to create candlesticks from it. You can build the 1 hour candlestick from the 1 minute candlestick. The [Hierarchical continuous aggregates][hcaggs] are very useful to save IO and processing time.

### Rollup

The [candlestick_agg][candlestick_agg] function returns a `candlesticksummary` object.

The rollup allows you to combine candlestick summaries into new structures from smaller timeframes to bigger timeframes without needing to reprocess all the data.

With this feature, you can group by the candlesticks multiple times saving processing from the server and make it easier to manage aggregations with different time intervals.

In the previous example, we used the `.candlestick` function that returns already the attributes from the different timeframes. In the SQL command it's calling the `open`, `high`, `low`, `close`, `volume`, and `vwap` functions that can access the values behind the candlesticksummary type.

To merge the candlesticks, the rollup method can aggregate several `candlesticksummary` objects into a bigger timeframe.

Let's rollup the structures:

```ruby
module Candlestick
  extend ActiveSupport::Concern

  included do
    # ... rest of the code remains the same

    scope :rollup, -> (timeframe: '1h') do
      bucket = %|time_bucket('#{timeframe}', "time_bucket")|
      select(bucket,"symbol",
            "rollup(candlestick) as candlestick")
      .group(1,2)
      .order(1)
    end
  end
end
```

Now, the new views in bigger timeframes can be added using it's own objects.

```ruby
ActiveRecord::Base.connection.instance_exec do
  options = -> (timeframe) {
    {
      with_data: false,
      refresh_policies: {
        start_offset: "INTERVAL '1 month'",
        end_offset: "INTERVAL '#{timeframe}'",
        schedule_interval: "INTERVAL '#{timeframe}'"
      }
    }
  }
  create_continuous_aggregate('candlestick_1h', Candlestick1m.rollup(timeframe: '1 hour'), **options['1 hour'])
  create_continuous_aggregate('candlestick_1d', Candlestick1h.rollup(timeframe: '1 day'),  **options['1 day'])
end
```

The final SQL executed to create the first [hierarchical continuous aggregates][hcaggs] is the following:

```sql
CREATE MATERIALIZED VIEW candlestick_1h
WITH (timescaledb.continuous) AS
  SELECT time_bucket('1 hour', "time_bucket"),
    "candlestick_1m"."symbol",
    rollup(candlestick) as candlestick
  FROM "candlestick_1m"
  GROUP BY 1, 2
  ORDER BY 1
WITH DATA;
```

So, as you can see all candlestick of one hour views follows the same interface of one minute, having the same column names and values, allowing to be reuse in larger timeframes.

### Refresh policy

Timescaledb is assuming you're storing real time data. Which means you can continuous feed the `ticks` table and aggregate the materialized data from time to time.

When `create_continuous_aggregate` is called with a `schedule_interval` it will also execute the following SQL line:

```sql
SELECT add_continuous_aggregate_policy('candlestick_1h',
  start_offset => INTERVAL '1 month',
  end_offset => INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');
```

Instead of updating the values row by row, the refresh policy will automatically run in background and aggregate the new data with the configured timeframe.

## Querying Continuous Aggregates with custom ActiveRecord models

With the `Candlestick1m` and `Candlestick1h` wrapping the continuous aggregates into models, now, it's time to explore the available scopes and what to do with it.

```ruby
Candlestick1m.yesterday.first
```

It will run the following SQL:
```sql
SELECT "candlestick_1m".*
FROM "candlestick_1m"
WHERE (DATE(time_bucket) = '2023-01-23') LIMIT 1;
```

And return the following object:

```ruby
#<Candlestick1m:0x000000010fbeff68
 time_bucket: 2023-01-23 00:00:00 UTC,
 symbol: "SYMBOL",
 candlestick:
  "(version:1,open:(ts:\"2023-01-23 00:00:00+00\",val:9),high:(ts:\"2023-01-23 00:00:10+00\",val:24),low:(ts:\"2023-01-23 00:00:50+00\",val:2),close:(ts:\"2023-01-23 00:00:50+00\",val:2),volume:Transaction(vol:2400,vwap:26200))",
 open: nil,
 open_time: nil,
 high: nil,
 high_time: nil,
 low: nil,
 low_time: nil,
 close: nil,
 close_time: nil,
 volume: nil,
 vwap: nil>
```

Note that the attributes are not available in the object but a `candlestick` attribute is present holding all the information. That's why it's necessary to use the `attributes` scope:
```ruby
Tick::CandlestickPerMinute.yesterday.attributes.first
```

Which will run the following query:
```sql
SELECT symbol, time_bucket,
  open(candlestick),
  high(candlestick),
  low(candlestick),
  close(candlestick),
  open_time(candlestick),
  high_time(candlestick),
  low_time(candlestick),
  close_time(candlestick),
  volume(candlestick),
  vwap(candlestick)
FROM "candlestick_1m"
WHERE (DATE(time_bucket) = '2023-01-23') LIMIT 1;
```

And the object will be filled with the attributes:

```ruby
=> {
 time_bucket: 2023-01-23 00:00:00 UTC,
 symbol: "SYMBOL",
 open: 0.9e1,
 open_time: 2023-01-23 00:00:00 +0000,
 high: 0.24e2,
 high_time: 2023-01-23 00:00:10 +0000,
 low: 0.2e1,
 low_time: 2023-01-23 00:00:50 +0000,
 close: 0.2e1,
 close_time: 2023-01-23 00:00:50 +0000,
 volume: 0.24e4,
 vwap: 0.1091666666666666e2
}
```

And from minute to one hour to a day:

```ruby
Tick::CandlestickPerMinute.rollup("'5 minutes'")
```

Both examples are just using the one minute continuous aggregates view and reprocessing it from there.

Composing the subqueries will probably be less efficient and unnecessary as we already created more continuous aggregates in the top of another continuous aggregates. Here is the SQL generated from the last nested rollups code:

```sql
SELECT symbol, time_bucket,
  open(candlestick),
  high(candlestick),
  low(candlestick),
  close(candlestick),
  open_time(candlestick),
  high_time(candlestick),
  low_time(candlestick),
  close_time(candlestick),
  volume(candlestick),
  vwap(candlestick)
FROM (
  SELECT time_bucket('1 day', "time_bucket"),
    symbol,
    rollup(candlestick) as candlestick
  FROM (
    SELECT time_bucket('1 hour', "time_bucket"),
      "candlestick_1m"."symbol",
      rollup(candlestick) as candlestick
    FROM "candlestick_1m" GROUP BY 1, 2 ORDER BY 1
  ) subquery GROUP BY 1, 2 ORDER BY 1
) subquery
```

## Plotting data

Now, the final step is plot the data using the javascript `plotly` library.

For this step, we're going to use a sinatra library to serve HTML and javascript and build the endpoints that will be consumed by the front end.

### The Sinatra App

```ruby
require 'sinatra/base'
require "sinatra/json"

class App < Sinatra::Base
  get '/candlestick.js' do
    send_file 'candlestick.js'
  end

  get '/candlestick_1m' do
    json({
      title: "Candlestick 1 minute last hour",
      data: Candlestick1m.last_hour.plotly_candlestick
    })
  end

  get '/candlestick_1h' do
    json({
      title: "Candlestick yesterday hourly",
      data: Candlestick1h.yesterday.plotly_candlestick
    })
  end

  get '/candlestick_1d' do
    json({
      title: "Candlestick daily this month",
      data: Candlestick1d.previous_week.plotly_candlestick
    })
  end

  get '/' do
<<-HTML
  <head>
    <script src="https://cdn.jsdelivr.net/npm/jquery@3.6.1/dist/jquery.min.js"></script>
    <script src='https://cdn.plot.ly/plotly-2.17.1.min.js'></script>
    <script src='/candlestick.js'></script>
  </head>
  <body>
    <div id='charts'>
  </body>
HTML
  end

  run! if app_file == $0
end
```

### Plotting data with Javascript

And the `candlesticks.js` file will be responsible for fetch data async and add new candlestick charts.

```javascript
let addChart = () => $('<div/>').appendTo('#charts')[0]
function ohlcChartFrom(url) {
  $.ajax({
    url: url,
    success: function(result) {
      let {data, title} = result;
      let {x, open, high, low, close, type} = data;
      open = open.map(parseFloat);
      high = high.map(parseFloat);
      low = low.map(parseFloat);
      close = close.map(parseFloat);
      var layout = {
        title: title, 
        dragmode: 'zoom',
        margin: { r: 10, t: 25, b: 40, l: 60 },
        showlegend: false,
        xaxis: {
          autorange: true,
          domain: [0, 1],
          title: 'Date',
          type: 'date'
        },
        yaxis: {
          autorange: true,
          domain: [0, 1],
          type: 'linear'
        }
      };

      ohlc = {x, open, high, low, close, type};
      Plotly.newPlot(addChart(), [ohlc], layout);
    }
  });
};

$( document ).ready(function() {
  ohlcChartFrom('/candlestick_1m');
  ohlcChartFrom('/candlestick_1h');
  ohlcChartFrom('/candlestick_1d');
});
```

Note that a new `plotly_candlestick` scope was mentioned in the view models and we need to add it to the `Candlestick` module to make it available for all the charts.

```ruby
module Candlestick
  extend ActiveSupport::Concern

  included do
    # ... rest of the code remains the same

    scope :plotly_candlestick, -> do
      data = attributes

      {
        type: 'candlestick',
        xaxis: 'x',
        yaxis: 'y',
        x: data.map(&:time_bucket),
        open: data.map(&:open),
        high: data.map(&:high),
        low: data.map(&:low),
        close: data.map(&:close)
      }
    end
  end
end
```

## Formatting time vectors

Another function from toolkit that can help you to prepare the data to plot is the `to_text` one from the toolkit. This is an experimental feature that allows you to prepare the JSON output using a template directly in the database to easily dump the output data without need to convert the data.

```ruby
module Candlestick
  extend ActiveSupport::Concern

  included do
    # ... rest of the code remains the same
    scope :time_vector_from_candlestick, -> ( attribute: "close") do
      select("timevector(time_bucket, #{attribute}(candlestick))")
    end

    scope :plotly_attribute,
      -> (attribute: "close",
          from: nil,
          template: %\'{"x": {{ TIMES | json_encode() | safe }}, "y": {{ VALUES | json_encode() | safe }}, "type": "scatter"}'\) do
      from ||= time_vector_from_candlestick(attribute: attribute)

      select("toolkit_experimental.to_text(tv.timevector, #{template})::json")
        .from("( #{from.to_sql} ) as tv")
        .first["to_text"]
    end
  end
end
```

The final SQL will look something like:

```sql
SELECT toolkit_experimental.to_text(
    tv.timevector,
    '{"x": {{ TIMES | json_encode() | safe }}, "y": {{ VALUES | json_encode() | safe }}, "type": "scatter"}'
  )::json
FROM (
  SELECT timevector(time_bucket, close(candlestick))
  FROM "candlestick_1h"
) as tv LIMIT 1
```