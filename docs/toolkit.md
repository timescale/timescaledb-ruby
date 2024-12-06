# The TimescaleDB Toolkit

The [TimescaleDB Toolkit][1] is an extension brought by [Timescale][2] for more
hyperfunctions, fully compatible with TimescaleDB and PostgreSQL.

They have almost no dependecy of hypertables but they play very well in the
hypertables ecosystem. The mission of the toolkit team is to ease all things
analytics when using TimescaleDB, with a particular focus on developer
ergonomics and performance.

Here, we're going to have a small walkthrough in some of the toolkit functions
and the helpers that can make simplify the generation of some complex queries.

!!!warning

    Note that we're just starting the toolkit integration in the gem and several
    functions are still experimental.

## The `add_toolkit_to_search_path!` helper

Several functions on the toolkit are still in experimental phase, and for that
reason they're not in the public schema, but lives in the `toolkit_experimental`
schema.

To use them without worring about the schema or prefixing it in all the cases,
you can introduce the schema as part of the [search_path][3].

To make it easy in the Ruby side, you can call the method directly from the
ActiveRecord connection:

```ruby
ActiveRecord::Base.connection.add_toolkit_to_search_path!
```

This statement is actually adding the [toolkit_experimental][4] to the search
path aside of the `public` and the `$user` variable path.

The statement can be placed right before your usage of the toolkit. For example,
if a single controller in your Rails app will be using it, you can create a
[filter][5] in the controller to set up it before the use of your action.

```ruby
class StatisticsController < ActionController::Base
  before_action :add_timescale_toolkit, only: [:complex_query]

  def complex_query
    # some code that uses the toolkit functions
  end

  protected
  def add_timescale_toolkit
    ActiveRecord::Base.connection.add_toolkit_to_search_path!
  end
```

## Example from scratch to use the Toolkit functions

Let's start by working on some example about the [volatility][6] algorithm.
This example is inspired in the [function pipelines][7] blog post, which brings
an example about how to calculate volatility and then apply the function 
pipelines to make the same with the toolkit.

!!!success

    Reading the [blog post][7] before trying this is highly recommended,
    and will give you more insights on how to apply and use time vectors that
    is our next topic.


Let's start by creating the `measurements` hypertable using a regular migration:

```ruby
class CreateMeasurements < ActiveRecord::Migration
  def change
    hypertable_options = {
      time_column: 'ts',
      chunk_time_interval: '1 day',
    }
    create_table :measurements, hypertable: hypertable_options, id: false do |t|
      t.integer :device_id
      t.decimal :val
      t.timestamp :ts
    end
  end
end
```

In this example, we just have a hypertable with no compression options. Every
`1 day` a new child table aka [chunk][8] will be generated. No compression
options for now.

Now, let's add the model `app/models/measurement.rb`:

```ruby
class Measurement < ActiveRecord::Base
  self.primary_key = nil

  acts_as_hypertable time_column: "ts"
end
```

At this moment, you can jump into the Rails console and start testing the model.

## Seeding some data

Before we build a very complex example, let's build something that is easy to
follow and comprehend. Let's create 3 records for the same device, representing
a hourly measurement of some sensor.

```ruby
yesterday = 1.day.ago
[1,2,3].each_with_index do |v,i|
  Measurement.create(device_id: 1, ts: yesterday + i.hour, val: v)
end
```

Every value is a progression from 1 to 3. Now, we can build a query to get the
values and let's build the example using plain Ruby.

```ruby
values = Measurement.order(:ts).pluck(:val) # => [1,2,3]
```

Using plain Ruby, we can build this example with a few lines of code:

```ruby
previous = nil
volatilities = values.map do |value|
  if previous
    delta = (value - previous).abs
    volatility = delta
  end
  previous = value
  volatility
end
# volatilities => [nil, 1, 1]
volatility = volatilities.compact.sum # => 2
```
Compact can be skipped and we can also build the sum in the same loop. So, a
refactored version would be:

```ruby
previous = nil
volatility = 0
values.each do |value|
  if previous
    delta = (value - previous).abs
    volatility += delta
  end
  previous = value
end
volatility # => 2
```

Now, it's time to move it to a database level calculating the volatility using
plain postgresql. A subquery is required to build the calculated delta, so it
seems a bit more confusing:


```ruby
delta = Measurement.select("device_id, abs(val - lag(val) OVER (PARTITION BY device_id ORDER BY ts)) as abs_delta")
Measurement
  .select("device_id, sum(abs_delta) as volatility")
  .from("(#{delta.to_sql}) as calc_delta")
  .group('device_id')
```

The final query for the example above looks like this:

```sql
SELECT device_id, SUM(abs_delta) AS volatility
FROM (
  SELECT device_id,
    ABS(
      val - LAG(val) OVER (
        PARTITION BY device_id ORDER BY ts)
      ) AS abs_delta
  FROM "measurements"
) AS calc_delta
GROUP BY device_id
```

It's much harder to understand the actual example then go with plain SQL and now
let's reproduce the same example using the toolkit pipelines:

```ruby
Measurement
  .select(<<-SQL).group("device_id")
    device_id,
    timevector(ts, val)
      -> sort()
      -> delta()
      -> abs()
      -> sum() as volatility
    SQL
```

As you can see, it's much easier to read and digest the example. Now, let's take
a look in how we can generate the queries using the scopes injected by the
`acts_as_hypertable` macro.


## Configuring the `segment_by` and `value_column`

Let's start changing the model to change the `acts_as_hypertable` to use the
`segment_by` and `value_column` options.

```ruby
class Measurement < ActiveRecord::Base
  acts_as_hypertable time_column: "ts",
    segment_by: "device_id",
    value_column: "val"
end
```

Now, that we have it, let's create a scope for it:

```ruby
class Measurement < ActiveRecord::Base
  acts_as_hypertable time_column: "ts",
    segment_by: "device_id",
    value_column: "val"

  scope :volatility, -> do
    select(<<-SQL).group("device_id")
      device_id,
      timevector(#{time_column}, #{value_column})
        -> sort()
        -> delta()
        -> abs()
        -> sum() as volatility
    SQL
  end
end
```

Now, we have created the volatility scope, grouping by device_id always.

In the Toolkit helpers, we have a similar version which also contains a default
segmentation based in the `segment_by` configuration done through the `acts_as_hypertable` macro. A method `segment_by_column` is added to access this configuration, so we can make a small change that makes you completely understand the volatility scope.

```ruby
class Measurement < ActiveRecord::Base
  acts_as_hypertable segment_by: "device_id",
    value_column: "val",
    time_column: "ts"

  scope :volatility, -> (columns=segment_by_column) do
    _scope = select([*columns,
        "timevector(#{time_column},
        #{value_column})
           -> sort()
           -> delta()
           -> abs()
           -> sum() as volatility"
    ].join(", "))
    _scope = _scope.group(columns) if columns
    _scope
  end
end
```

Testing the method:

```ruby
Measurement.volatility.map(&:attributes)
# DEBUG -- : Measurement Load (1.6ms)  SELECT device_id, timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility FROM "measurements" GROUP BY "measurements"."device_id"
# => [{"device_id"=>1, "volatility"=>8.0}]
```

Let's add a few more records with random values:

```ruby
yesterday = 1.day.ago
(2..6).each do |d|
  (1..10).each do |j|
    Measurement.create(device_id: d, ts: yesterday + j.hour, val: rand(10))
  end
end
```

Testing all the values:

```ruby
 Measurement.order("device_id").volatility.map(&:attributes)
 # DEBUG -- : Measurement Load (1.3ms)  SELECT device_id, timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility FROM "measurements" GROUP BY "measurements"."device_id" ORDER BY device_id
=> [{"device_id"=>1, "volatility"=>8.0},
 {"device_id"=>2, "volatility"=>24.0},
 {"device_id"=>3, "volatility"=>30.0},
 {"device_id"=>4, "volatility"=>32.0},
 {"device_id"=>5, "volatility"=>44.0},
 {"device_id"=>6, "volatility"=>23.0}]
```

If the parameter is explicit `nil` it will not group by:

```ruby
Measurement.volatility(nil).map(&:attributes)
# DEBUG -- : Measurement Load (5.4ms)  SELECT timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility FROM "measurements"
# => [{"volatility"=>186.0, "device_id"=>nil}]
```

## Comparing with Ruby version

Now, it's time to benchmark and compare Ruby vs PostgreSQL solutions, verifying
which is faster:

```ruby
class Measurement < ActiveRecord::Base
  # code you already know
  scope :volatility_by_device_id, -> {
    volatility = Hash.new(0)
    previous = Hash.new
    find_all do |measurement|
      device_id = measurement.device_id
      if previous[device_id]
        delta = (measurement.val - previous[device_id]).abs
        volatility[device_id] += delta
      end
      previous[device_id] = measurement.val
    end
    volatility
  }
end
```

Now, benchmarking the real time to compute it on Ruby in milliseconds.

```ruby
Benchmark.measure { Measurement.volatility_by_device_id }.real * 1000
# => 3.021999917924404
```

## Seeding massive data

Now, let's use `generate_series` to fast insert a lot of records directly into
the database and make it full of records.

Let's just agree on some numbers to have a good start. Let's generate data for
5 devices emitting values every 5 minutes, which will generate around 50k
records.

Let's use some plain SQL to insert the records now:

```ruby
sql = "INSERT INTO measurements (ts, device_id, val)
SELECT ts, device_id, random()*80
FROM generate_series(TIMESTAMP '2022-01-01 00:00:00',
                   TIMESTAMP '2022-02-01 00:00:00',
             INTERVAL '5 minutes') AS g1(ts),
      generate_series(0, 5) AS g2(device_id);
"
ActiveRecord::Base.connection.execute(sql)
```

In my MacOS M1 processor it took less than a second to insert the 53k records:

```ruby
# DEBUG (177.5ms)  INSERT INTO measurements (ts, device_id, val) ..
# => #<PG::Result:0x00007f8152034168 status=PGRES_COMMAND_OK ntuples=0 nfields=0 cmd_tuples=53574>
```

Now, let's measure compare the time to process the volatility:

```ruby
Benchmark.bm do |x|
  x.report("ruby")  { pp Measurement.volatility_by_device_id }
  x.report("sql") { pp Measurement.volatility("device_id").map(&:attributes) }
end
#           user     system      total        real
# ruby    0.612439   0.061890   0.674329 (  0.727590)
# sql     0.001142   0.000301   0.001443 (  0.060301)
```

Calculating the performance ratio we can see `0.72 / 0.06` means that SQL is 12
times faster than Ruby to process volatility 🎉

Just considering it was localhost, we don't have the internet to pass all the
records over the wires. Now, moving to a remote host look the numbers:

!!!warning
    Note that the previous numbers where using localhost.
    Now, using a remote connection between different regions,
    it looks even ~500 times slower than SQL.

                user     system      total        real
        ruby 0.716321   0.041640   0.757961 (  6.388881)
        sql  0.001156   0.000177   0.001333 (  0.161270)

Let’s recap what’s time consuming here. The `find_all` is just not optimized to
fetch the data and also consuming most of the time here. It’s also fetching
the data and converting it to ActiveRecord model which has thousands of methods.

It’s very comfortable but just need the attributes to make it.

Let’s optimize it by plucking an array of values grouped by device.

```ruby
class Measurement < ActiveRecord::Base
  # ...
  scope :values_from_devices, -> {
    ordered_values = select(:val, :device_id).order(:ts)
    Hash[
      from(ordered_values)
      .group(:device_id)
      .pluck("device_id, array_agg(val)")
    ]
  }
end
```

Now, let's create a method for processing volatility.

```ruby
class Volatility
  def self.process(values)
    previous = nil
    deltas = values.map do |value|
      if previous
        delta = (value - previous).abs
        volatility = delta
      end
      previous = value
      volatility
    end
    #deltas => [nil, 1, 1]
    deltas.shift
    volatility = deltas.sum
  end
  def self.process_values(map)
    map.transform_values(&method(:process))
  end
end
```

Now, let's change the benchmark to expose the time for fetching and processing:


```ruby
volatilities = nil

ActiveRecord::Base.logger = nil
Benchmark.bm do |x|
  x.report("ruby")  { Measurement.volatility_ruby }
  x.report("sql") { Measurement.volatility_sql.map(&:attributes)  }
  x.report("fetch") { volatilities =  Measurement.values_from_devices }
  x.report("process") { Volatility.process_values(volatilities) }
end
```

Checking the results:

          user     system      total        real
    ruby  0.683654   0.036558   0.720212 (  0.743942)
    sql  0.000876   0.000096   0.000972 (  0.054234)
    fetch  0.078045   0.003221   0.081266 (  0.116693)
    process  0.067643   0.006473   0.074116 (  0.074122)

Much better, now we can see only 200ms difference between real time which means ~36% more.


If we try to break down a bit more of the SQL part, we can see that the 

```sql
EXPLAIN ANALYSE
  SELECT device_id, array_agg(val)
  FROM (
    SELECT val, device_id
    FROM measurements
    ORDER BY ts ASC
  ) subquery
  GROUP BY device_id;
```

We can check the execution time and make it clear how much time is necessary
just for the processing part, isolating network and the ActiveRecord layer.

    │ Planning Time: 17.761 ms                                                                                                                                                                     │
    │ Execution Time: 36.302 ms

So, it means that from the **116ms** to fetch the data, only **54ms** was used from the DB
and the remaining **62ms** was consumed by network + ORM.

[1]: https://github.com/timescale/timescaledb-toolkit
[2]: https://timescale.com
[3]: https://www.postgresql.org/docs/14/runtime-config-client.html#GUC-SEARCH-PATH
[4]: https://github.com/timescale/timescaledb-toolkit/blob/main/docs/README.md#a-note-on-tags-
[5]: https://guides.rubyonrails.org/action_controller_overview.html#filters
[6]: https://en.wikipedia.org/wiki/Volatility_(finance)
[7]: https://www.timescale.com/blog/function-pipelines-building-functional-programming-into-postgresql-using-custom-operators/
[8]: https://docs.timescale.com/timescaledb/latest/overview/core-concepts/hypertables-and-chunks/#partitioning-in-hypertables-with-chunks
