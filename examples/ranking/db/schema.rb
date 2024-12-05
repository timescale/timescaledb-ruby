# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 0) do
  create_schema "_timescaledb_cache"
  create_schema "_timescaledb_debug"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "plpgsql"
  enable_extension "timescaledb"
  enable_extension "timescaledb_toolkit"

  create_table "network_device_data", id: false, force: :cascade do |t|
    t.timestamptz "time", null: false
    t.integer "device", null: false
    t.integer "id", null: false
    t.bigint "counter32bit"
    t.bigint "counter64bit"
    t.index ["time"], name: "network_device_data_time_idx", order: :desc
  end

  create_table "pages", id: false, force: :cascade do |t|
    t.timestamptz "time", null: false
    t.text "url", null: false
    t.float "time_to_fetch"
    t.text "title", null: false
    t.text "headers", default: [], array: true
    t.jsonb "links"
    t.text "body", default: [], array: true
    t.text "codeblocks", default: [], array: true
    t.integer "html_size"
    t.tsvector "search_vector"
    t.index ["search_vector"], name: "pages_search_vector_idx", using: :gin
    t.index ["time"], name: "pages_time_idx", order: :desc
  end

  create_table "sample", id: false, force: :cascade do |t|
    t.timestamptz "time", null: false
    t.text "device_id", null: false
    t.float "value", null: false
    t.index ["time"], name: "sample_time_idx", order: :desc
  end

  create_table "ticks", id: false, force: :cascade do |t|
    t.timestamptz "time", null: false
    t.text "symbol", null: false
    t.decimal "price", null: false
    t.decimal "volume", null: false
    t.index ["time"], name: "ticks_time_idx", order: :desc
  end


  create_view "network_data_final", sql_definition: <<-SQL
      SELECT id,
      bucket,
      interpolated_rate(counter32bit_agg, bucket, 'PT1M'::interval, lag(counter32bit_agg) OVER (PARTITION BY id ORDER BY bucket), lead(counter32bit_agg) OVER (PARTITION BY id ORDER BY bucket)) AS counter32bitrate,
      interpolated_rate(counter64bit_agg, bucket, 'PT1M'::interval, lag(counter64bit_agg) OVER (PARTITION BY id ORDER BY bucket), lead(counter64bit_agg) OVER (PARTITION BY id ORDER BY bucket)) AS counter64bitrate
     FROM network_data_agg_1min
    ORDER BY id, bucket;
  SQL
  create_view "network_data_final_with_resets", sql_definition: <<-SQL
      WITH counter_data AS (
           SELECT network_device_data."time",
              network_device_data.device,
              network_device_data.id,
              network_device_data.counter64bit,
              lag(network_device_data.counter64bit) OVER (PARTITION BY network_device_data.device, network_device_data.id ORDER BY network_device_data."time") AS prev_counter64bit
             FROM network_device_data
          ), resets_detected AS (
           SELECT counter_data."time",
              counter_data.device,
              counter_data.id,
              counter_data.counter64bit,
              counter_data.prev_counter64bit,
                  CASE
                      WHEN (counter_data.counter64bit < counter_data.prev_counter64bit) THEN 1
                      ELSE 0
                  END AS reset_detected
             FROM counter_data
          ), rate_calculation AS (
           SELECT resets_detected."time",
              resets_detected.device,
              resets_detected.id,
              resets_detected.counter64bit,
              resets_detected.prev_counter64bit,
              resets_detected.reset_detected,
                  CASE
                      WHEN (resets_detected.reset_detected = 1) THEN (((resets_detected.counter64bit)::numeric + ('18446744073709551615'::numeric - (COALESCE(resets_detected.prev_counter64bit, (0)::bigint))::numeric)) / EXTRACT(epoch FROM (resets_detected."time" - lag(resets_detected."time") OVER (PARTITION BY resets_detected.device, resets_detected.id ORDER BY resets_detected."time"))))
                      ELSE (((resets_detected.counter64bit - COALESCE(resets_detected.prev_counter64bit, resets_detected.counter64bit)))::numeric / EXTRACT(epoch FROM (resets_detected."time" - lag(resets_detected."time") OVER (PARTITION BY resets_detected.device, resets_detected.id ORDER BY resets_detected."time"))))
                  END AS rate
             FROM resets_detected
          )
   SELECT "time",
      device,
      id,
      rate
     FROM rate_calculation
    ORDER BY "time", device, id;
  SQL
  create_view "ohlcv_1m", sql_definition: <<-SQL
      SELECT bucket,
      symbol,
      open(candlestick) AS open,
      high(candlestick) AS high,
      low(candlestick) AS low,
      close(candlestick) AS close,
      volume(candlestick) AS volume,
      vwap(candlestick) AS vwap
     FROM _ohlcv_1m;
  SQL
  create_view "ohlcv_1h", sql_definition: <<-SQL
      SELECT bucket,
      symbol,
      open(candlestick) AS open,
      high(candlestick) AS high,
      low(candlestick) AS low,
      close(candlestick) AS close,
      volume(candlestick) AS volume,
      vwap(candlestick) AS vwap
     FROM _ohlcv_1h;
  SQL
  create_view "ohlcv_1d", sql_definition: <<-SQL
      SELECT bucket,
      symbol,
      open(candlestick) AS open,
      high(candlestick) AS high,
      low(candlestick) AS low,
      close(candlestick) AS close,
      volume(candlestick) AS volume,
      vwap(candlestick) AS vwap
     FROM _ohlcv_1d;
  SQL
  create_hypertable "network_device_data", time_column: "time", chunk_time_interval: "7 days"
  create_hypertable "pages", time_column: "time", chunk_time_interval: "1 day"
  create_hypertable "sample", time_column: "time", chunk_time_interval: "7 days"
  create_hypertable "ticks", time_column: "time", chunk_time_interval: "1 day", compress_segmentby: "symbol", compress_orderby: "time ASC", compress_after: "7 days"
  create_continuous_aggregate("network_data_agg_1min", <<-SQL, , materialized_only: true, finalized: true)
    SELECT time_bucket('PT1M'::interval, "time") AS bucket,
      device,
      id,
      counter_agg("time", (counter32bit)::double precision) AS counter32bit_agg,
      counter_agg("time", (counter64bit)::double precision) AS counter64bit_agg
     FROM network_device_data
    GROUP BY (time_bucket('PT1M'::interval, "time")), device, id
  SQL

  create_continuous_aggregate("_ohlcv_1m", <<-SQL, , materialized_only: false, finalized: true)
    SELECT time_bucket('PT1M'::interval, "time") AS bucket,
      symbol,
      candlestick_agg("time", (price)::double precision, (volume)::double precision) AS candlestick
     FROM ticks
    GROUP BY (time_bucket('PT1M'::interval, "time")), symbol
  SQL

  create_continuous_aggregate("_ohlcv_1h", <<-SQL, , materialized_only: true, finalized: true)
    SELECT time_bucket('PT1H'::interval, bucket) AS bucket,
      symbol,
      rollup(candlestick) AS candlestick
     FROM _ohlcv_1m
    GROUP BY (time_bucket('PT1H'::interval, bucket)), symbol
  SQL

  create_continuous_aggregate("_ohlcv_1d", <<-SQL, , materialized_only: true, finalized: true)
    SELECT time_bucket('P1D'::interval, bucket) AS bucket,
      symbol,
      rollup(candlestick) AS candlestick
     FROM _ohlcv_1h
    GROUP BY (time_bucket('P1D'::interval, bucket)), symbol
  SQL

  create_continuous_aggregate("stats_agg_1m_sample", <<-SQL, refresh_policies: { start_offset: "INTERVAL '00:05:00'", end_offset: "INTERVAL '00:01:00'", schedule_interval: "INTERVAL '60'"}, materialized_only: false, finalized: true)
    SELECT time_bucket('PT1M'::interval, "time") AS bucket,
      device_id,
      stats_agg(value) AS stats_agg
     FROM sample
    GROUP BY (time_bucket('PT1M'::interval, "time")), device_id
  SQL

  create_continuous_aggregate("stats_agg_1h_sample", <<-SQL, refresh_policies: { start_offset: "INTERVAL '03:00:00'", end_offset: "INTERVAL '01:00:00'", schedule_interval: "INTERVAL '5'"}, materialized_only: false, finalized: true)
    SELECT time_bucket('PT1H'::interval, bucket) AS bucket,
      device_id,
      rollup(stats_agg) AS stats_agg
     FROM stats_agg_1m_sample
    GROUP BY (time_bucket('PT1H'::interval, bucket)), device_id
  SQL

  create_continuous_aggregate("stats_agg_1d_sample", <<-SQL, refresh_policies: { start_offset: "INTERVAL '3 days'", end_offset: "INTERVAL '01:00:00'", schedule_interval: "INTERVAL '5'"}, materialized_only: false, finalized: true)
    SELECT time_bucket('P1D'::interval, bucket) AS bucket,
      device_id,
      rollup(stats_agg) AS stats_agg
     FROM stats_agg_1h_sample
    GROUP BY (time_bucket('P1D'::interval, bucket)), device_id
  SQL

  create_continuous_aggregate("stats_agg_monthly_sample", <<-SQL, refresh_policies: { start_offset: "INTERVAL '3 mons'", end_offset: "INTERVAL '01:00:00'", schedule_interval: "INTERVAL '5'"}, materialized_only: false, finalized: true)
    SELECT time_bucket('P1M'::interval, bucket) AS bucket,
      device_id,
      rollup(stats_agg) AS stats_agg
     FROM stats_agg_1d_sample
    GROUP BY (time_bucket('P1M'::interval, bucket)), device_id
  SQL

end
