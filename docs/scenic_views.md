# Scenic Integration

The [Scenic](https://github.com/scenic-views/scenic) gem provides a way to create
versioned database views in Rails. If you're using Scenic, the Timescaledb gem
will automatically detect it and already integrate into your code.

### Migration script

Use the `create_scenic_continuous_aggregate` macro to invoke your materialized
view.

```ruby
class CreateScorePerHours < ActiveRecord::Migration[7.0]
  def change
    create_scenic_continuous_aggregate :score_per_hours
  end
end
```

### Define the view in a sql file

The sql file should be placed in the `db/views` directory. The file should be
named after the view and the version number. For example, `score_per_hours_v01.sql`.

```sql
SELECT game_id,
       time_bucket(INTERVAL '1 hour', created_at) AS bucket,
       AVG(score),
       MAX(score),
       MIN(score)
FROM plays
GROUP BY game_id, bucket;
```

Check out the source code of the [full example](https://github.com/timescale/timescaledb-ruby/tree/master/examples/ranking).
