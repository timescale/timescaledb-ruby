
def setup_tables
  ActiveRecord::Schema.define(version: 1) do
    hypertable_options = { chunk_time_interval: '1 min', compress_segmentby: 'identifier', compress_after: '7 days' }

    create_table(:events, id: false, hypertable: hypertable_options) do |t|
      t.string :identifier, null: false
      t.jsonb :payload
      t.datetime :created_at
    end

    create_table(:hypertable_with_options, id: false, hypertable: {
      time_column: :ts,
      chunk_time_interval: '5 min',
      compress_segmentby: 'identifier',
      compress_orderby: 'ts',
      compress_after: '15 min',
      drop_after: '1 hour',
      if_not_exists: true
    }) do |t|
      t.serial :id, primary_key: false
      t.datetime :ts
      t.string :identifier
      t.index [:id, :ts], name: "index_hypertable_with_options_on_id_and_ts"
    end

    create_table(:hypertable_with_id_partitioning, hypertable: {
      time_column: 'id',
      chunk_time_interval: 1_000_000
    })

    create_table(:non_hypertables) do |t|
      t.string :name
    end
  end
end

def teardown_tables
  Timescaledb::ContinuousAggregates.all.each do |continuous_aggregate|
    ActiveRecord::Base.connection.execute("DROP MATERIALIZED VIEW IF EXISTS #{continuous_aggregate.view_name} CASCADE")
  end

  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table, force: :cascade)
  end
end
