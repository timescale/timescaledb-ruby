# OHLC / Candlesticks


Candlesticks are a popular tool in technical analysis, used by traders to determine potential market movements.

The toolkit also allows you to compute candlesticks with the [candlestick][1] function.

Candlesticks are a type of price chart that displays the high, low, open, and close prices of a security for a specific period. They can be useful because they can provide information about market trends and reversals. For example, if you see that the stock has been trading in a range for a while, it may be worth considering buying or selling when the price moves outside of this range. Additionally, candlesticks can be used in conjunction with other technical indicators to make trading decisions.


Let's start defining a table that stores the trades from financial market data
and then we can calculate the candlesticks with the Timescaledb Toolkit.

## Migration

The `ticks` table is a hypertable that will be partitioning the data into one
week intervl. Compressing them after a month to save storage.

```ruby
hypertable_options = {
  time_column: 'time',
  chunk_time_interval: '1 week',
  compress_segmentby: 'symbol',
  compress_orderby: 'time',
  compress_after: '1 month'
}
create_table :ticks, hypertable: hypertable_options, id: false do |t|
  t.timestampt :time
  t.string :symbol
  t.decimal :price
  t.integer :volume
end
```

In the previous code block, we assume it goes inside a Rails migration or you
can embed such code into a `ActiveRecord::Base.connection.instance_exec` block.

## Defining the model

As we don't need a primary key for the table, let's set it to nil. The
`acts_as_hypertable` macro will give us several useful scopes that can be
wrapping some of the TimescaleDB features.

The `acts_as_time_vector` will allow us to set what are the default columns used
to calculate the data.


```ruby
class Tick < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable time_column: :time
  acts_as_time_vector value_column: price, segment_by: :symbol
end
```

The candlestick will split the timeframe by the `time_column` and use the `price` as the default value to process the candlestick. It will also segment the candles by `symbol`.

If you need to generate some data for your table, please check [this post][2].

## The 'candlestick' scope

When the `acts_as_time_vector` method is used in the model, it will inject
several scopes from the toolkit to easily have access to functions like the
candlestick.

The `candlestick` scope is available with a few parameters that inherits the
configuration from the `acts_as_time_vector` declared previously.

The simplest query is:

```ruby
Tick.candlestick(timeframe: '1m', price: :price, volume: :volume)
```

It will generate the following SQL:

```sql
 SELECT symbol,
    "time",
    open(ohlc),
    high(ohlc),
    low(ohlc),
    close(ohlc),
    open_time(ohlc),
    high_time(ohlc),
    low_time(ohlc),
    close_time(ohlc)
FROM (
    SELECT time_bucket('1m', time) as time,
      "ticks"."symbol",
      candlestick_agg(time, price, volume)
    FROM "ticks" GROUP BY 1, 2 ORDER BY 1)
AS ohlc
```

The timeframe argument can also be skipped and the default is `1 hour`.

You can also combine other scopes to filter data before you get the data from the candlestick:

```ruby
Tick.yesterday
  .where(symbol: "APPL")
  .ohlc(timeframe: '1m')
```

The `yesterday` scope is automatically included because of the `acts_as_hypertable` macro. And it will be combining with other where clauses.

## Continuous aggregates

If you would like to continuous aggregate the candlesticks on a materialized
view you can use continuous aggregates for it.

The next examples shows how to create a continuous aggregates of 1 minute
candlesticks:

```ruby
options = {
  with_data: false,
  refresh_policies: {
    start_offset: "INTERVAL '1 month'",
    end_offset: "INTERVAL '1 minute'",
    schedule_interval: "INTERVAL '1 minute'"
  }
}
create_continuous_aggregate('ohlc_1m', Tick.ohlc(timeframe: '1m'), **options)
```


Note that the `create_continuous_aggregate` calls the `to_sql` method in case
the second parameter is not a string.

## Rollup

The rollup allows you to combine ohlc structures from smaller timeframes
to bigger timeframes without needing to reprocess all the data.

With this feature, you can group by the ohcl multiple times saving processing 
from the server and make it easier to manage candlesticks from different time intervals.

In the previous example, we used the `.ohlc` function that returns already the
attributes from the different timeframes. In the SQL command it's calling the
`open`, `high`, `low`, `close` functions that can access the values behind the
ohlcsummary type.

To merge the ohlc we need to rollup the `ohlcsummary` to a bigger timeframe and
only access the values as a final resort to see them and access as attributes.

Let's rebuild the structure:

```ruby
execute "CREATE VIEW ohlc_1h AS #{ Ohlc1m.rollup(timeframe: '1 hour').to_sql}"
execute "CREATE VIEW ohlc_1d AS #{ Ohlc1h.rollup(timeframe: '1 day').to_sql}"
```

## Defining models for views

Note that the previous code refers to `Ohlc1m` and `Ohlc1h` as two classes that
are not defined yet. They will basically be ActiveRecord readonly models to
allow to build scopes from it.

Ohlc for one hour:
```ruby
class Ohlc1m < ActiveRecord::Base
  self.table_name = 'ohlc_1m'
  include Ohlc
end
```

Ohlc for one day is pretty much the same:
```ruby
class Ohlc1h < ActiveRecord::Base
  self.table_name = 'ohlc_1h'
  include Ohlc
end
```

We'll also have the `Ohlc` as a shared concern that can help you to reuse
queries in different views.

```ruby
module Ohlc
  extend ActiveSupport::Concern

  included do
    scope :rollup, -> (timeframe: '1h') do
      select("symbol, time_bucket('#{timeframe}', time) as time,
            toolkit_experimental.rollup(ohlc) as ohlc")
      .group(1,2)
    end

    scope :attributes, -> do
      select("symbol, time,
        toolkit_experimental.open(ohlc),
        toolkit_experimental.high(ohlc),
        toolkit_experimental.low(ohlc),
        toolkit_experimental.close(ohlc),
        toolkit_experimental.open_time(ohlc),
        toolkit_experimental.high_time(ohlc),
        toolkit_experimental.low_time(ohlc),
        toolkit_experimental.close_time(ohlc)")
    end

    # Following the attributes scope, we can define accessors in the
    # model to populate from the previous scope to make it similar
    # to a regular model structure.
    attribute :time, :time
    attribute :symbol, :string

    %w[open high low close].each do |name|
      attribute name, :decimal
      attribute "#{name}_time", :time
    end

    def readonly?
      true
    end
  end
end
```

The `rollup` scope is the one that was used to redefine the data into big timeframes
and the `attributes` allow to access the attributes from the [OpenHighLowClose][3]
type.

In this way, the views become just shortcuts and complex sql can also be done
just nesting the model scope. For example, to rollup from a minute to a month,
you can do:

```ruby
Ohlc1m.attributes.from(
  Ohlc1m.rollup(timeframe: '1 month')
)
```

Soon the continuous aggregates will [support nested aggregates][4] and you'll be
abble to define the materialized views with steps like this:


```ruby
Ohlc1m.attributes.from(
  Ohlc1m.rollup(timeframe: '1 month').from(
    Ohlc1m.rollup(timeframe: '1 week').from(
      Ohlc1m.rollup(timeframe: '1 day').from(
        Ohlc1m.rollup(timeframe: '1 hour')
      )
    )
  )
)
```

For now composing the subqueries will probably be less efficient and unnecessary.
But the foundation is already here to help you in future analysis. Just to make
it clear, here is the SQL generated from the previous code:

```sql
SELECT symbol,
    time,
    toolkit_experimental.open(ohlc),
    toolkit_experimental.high(ohlc),
    toolkit_experimental.low(ohlc),
    toolkit_experimental.close(ohlc),
    toolkit_experimental.open_time(ohlc),
    toolkit_experimental.high_time(ohlc),
    toolkit_experimental.low_time(ohlc),
    toolkit_experimental.close_time(ohlc)
FROM (
    SELECT symbol,
        time_bucket('1 month', time) as time,
        toolkit_experimental.rollup(ohlc) as ohlc
    FROM (
        SELECT symbol,
            time_bucket('1 week', time) as time,
            toolkit_experimental.rollup(ohlc) as ohlc
        FROM (
            SELECT symbol,
                time_bucket('1 day', time) as time,
                toolkit_experimental.rollup(ohlc) as ohlc
            FROM (
                SELECT symbol,
                    time_bucket('1 hour', time) as time,
                    toolkit_experimental.rollup(ohlc) as ohlc
                FROM "ohlc_1m"
                GROUP BY 1, 2
            ) subquery
            GROUP BY 1, 2
        ) subquery
        GROUP BY 1, 2
    ) subquery
    GROUP BY 1, 2
) subquery
```

You can also define more scopes that will be useful depending on what are you
working on. Example:

```ruby
scope :yesterday, -> { where("DATE(#{time_column}) = ?", Date.yesterday.in_time_zone.to_date) }
```

And then, just combine the scopes:

```ruby
Ohlc1m.yesterday.attributes
```
I hope you find this tutorial interesting and you can also check the
`ohlc.rb` file in the [examples/toolkit-demo][5] folder.

If you have any questions or concerns, feel free to reach me ([@jonatasdp][7]) in the [Timescale community][6] or tag timescaledb in your StackOverflow issue.

[1]: https://docs.timescale.com/api/latest/hyperfunctions/financial-analysis/ohlc/
[2]: https://ideia.me/timescale-continuous-aggregates-with-ruby
[3]: https://github.com/timescale/timescaledb-toolkit/blob/cbbca7b2e69968e585c845924e7ed7aff1cea20a/extension/src/ohlc.rs#L20-L24
[4]: https://github.com/timescale/timescaledb/pull/4668
[5]: https://github.com/timescale/timescaledb-ruby/tree/master/examples/toolkit-demo
[6]: https://timescale.com/community
[7]: https://twitter.com/jonatasdp
