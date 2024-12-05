RSpec.describe Timescaledb::SchemaDumper, database_cleaner_strategy: :truncation do
  let(:con) { ActiveRecord::Base.connection }

  let(:query) do
    Event.select("time_bucket('1m', created_at) as time,
                  identifier as label,
                  count(*) as value").group("1,2")
  end
  let(:query_daily) do
    Event
      .from("event_counts")
      .select("time_bucket('1d', time) as time,
              sum(value) as value").group("1")
  end

  context "schema" do
    it "should include the timescaledb extension" do
      dump = dump_output
      expect(dump).to include 'enable_extension "timescaledb"'
      expect(dump).to include 'enable_extension "timescaledb_toolkit"'
    end

    it "should skip internal schemas" do
      dump = dump_output
      expect(dump).not_to include 'create_schema "_timescaledb_cache"'
      expect(dump).not_to include 'create_schema "_timescaledb_config"'
      expect(dump).not_to include 'create_schema "_timescaledb_catalog"'
      expect(dump).not_to include 'create_schema "_timescaledb_debug"'
      expect(dump).not_to include 'create_schema "_timescaledb_functions"'
      expect(dump).not_to include 'create_schema "_timescaledb_internal"'
      expect(dump).not_to include 'create_schema "timescaledb_experimental"'
      expect(dump).not_to include 'create_schema "timescaledb_information"'
      expect(dump).not_to include 'create_schema "toolkit_experimental"'
    end
  end

  context "hypertables" do
    let(:sorted_hypertables) do
      %w[events hypertable_with_options migration_tests]
    end

    it "dump the create_table sorted by hypertable_name" do
      previous = 0
      dump = dump_output
      sorted_hypertables.each do |name|
        index = dump.index(%|create_hypertable "#{name}"|)
        if index.nil?
          puts "couldn't find hypertable #{name} in the output", dump
        end
        expect(index).to be > previous
        previous = index
      end
    end

    context "with retention policies" do
      before do
        con.create_retention_policy("events", drop_after: "1 week")
      end
      after do
        con.remove_retention_policy("events")
      end

      it "add retention policies after hypertables" do
        dump = dump_output
        last_hypertable = dump.index(%|create_hypertable "#{sorted_hypertables.last}"|)
        index = dump.index(%|create_retention_policy "events", interval: "P7D"|)
        expect(index).to be > last_hypertable
      end
    end
  end

  let(:dump_output) do
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(con, stream)
    stream.string
  end

  it "dumps a create_continuous_aggregate for a view in the database" do
    con.execute("DROP MATERIALIZED VIEW IF EXISTS event_daily_counts")
    con.execute("DROP MATERIALIZED VIEW IF EXISTS event_counts")
    con.create_continuous_aggregate(:event_counts, query, materialized_only: true, finalized: true)
    con.create_continuous_aggregate(:event_daily_counts, query_daily, materialized_only: true, finalized: true)

    if defined?(Scenic)
      Scenic.load # Normally this happens in a railtie, but we aren't loading a full rails env here
      con.execute("DROP VIEW IF EXISTS searches")
      con.create_view :searches, sql_definition: "SELECT 'needle'::text AS haystack"
    end

    dump = dump_output

    expect(dump).to include 'create_continuous_aggregate("event_counts"'
    expect(dump).to include 'materialized_only: true, finalized: true'

    expect(dump).not_to include ', ,'
    expect(dump).not_to include 'create_view "event_counts"' # Verify Scenic ignored this view
    expect(dump).to include 'create_view "searches", sql_definition: <<-SQL' if defined?(Scenic)

    hypertable_creation = dump.index('create_hypertable "events"')
    caggs_creation = dump.index('create_continuous_aggregate("event_counts"')

    expect(hypertable_creation).to be < caggs_creation

    caggs_dependent_creation = dump.index('create_continuous_aggregate("event_daily_counts"')
    expect(caggs_creation).to be < caggs_dependent_creation
  end

  describe "dumping hypertable options" do
    before(:each) do
      con.drop_table :partition_by_hash_tests, force: :cascade, if_exists: true
      con.drop_table :partition_by_range_tests, force: :cascade, if_exists: true
      con.drop_table :partition_by_integer_tests, force: :cascade, if_exists: true
    end

    it "extracts by_hash options" do
      options = { partition_column: "category", number_partitions: 3, create_default_indexes: false }

      con.create_table :partition_by_hash_tests, id: false, hypertable: options do |t|
        t.string :category
        t.datetime :created_at, default: -> { "now()" }
        t.index [:category, :created_at], unique: true, name: "index_partition_by_hash_tests_on_category_and_created_at"
      end

      dump = dump_output

      expect(dump).to include 'create_hypertable "partition_by_hash_tests", time_column: "created_at", chunk_time_interval: "7 days", partition_column: "category", number_partitions: 3, create_default_indexes: false'
    end

    it "extracts index options" do
      options = { create_default_indexes: false }
      con.create_table :partition_by_range_tests, id: false, hypertable: options do |t|
        t.timestamps
      end

      dump = dump_output

      expect(dump).to include 'create_hypertable "partition_by_range_tests", time_column: "created_at", chunk_time_interval: "7 days"'
    end

    it "extracts integer chunk_time_interval" do
      options = { time_column: :id, chunk_time_interval: 10000 }
      con.create_table :partition_by_integer_tests, hypertable: options do |t|
        t.timestamps
      end

      dump = dump_output

      expect(dump).to include 'create_hypertable "partition_by_integer_tests", time_column: "id", chunk_time_interval: 10000'
    end

    context "compress_segmentby" do
      before(:each) do
        con.drop_table :segmentby_tests, force: :cascade if con.table_exists?(:segmentby_tests)
      end

      it "handles multiple compress_segmentby" do
        options = { compress_segmentby: "identifier,second_identifier" }
        con.create_table :segmentby_tests, hypertable: options, id: false do |t|
          t.string :identifier
          t.string :second_identifier
          t.timestamps
        end

        dump = dump_output

        expect(dump).to include 'create_hypertable "segmentby_tests", time_column: "created_at", chunk_time_interval: "7 days", compress_segmentby: "identifier, second_identifier", compress_orderby: "created_at ASC"'
      end
    end

    context "compress_orderby" do
      before(:each) do
        con.drop_table :orderby_tests, force: :cascade if con.table_exists?(:orderby_tests)
      end

      context "ascending order" do
        context "nulls first" do
          it "extracts compress_orderby correctly" do
            options = { compress_segmentby: "identifier", compress_orderby: "created_at ASC NULLS FIRST" }
            con.create_table :orderby_tests, hypertable: options, id: false do |t|
              t.string :identifier
              t.timestamps
            end

            dump = dump_output

            expect(dump).to include 'create_hypertable "orderby_tests", time_column: "created_at", chunk_time_interval: "7 days", compress_segmentby: "identifier", compress_orderby: "created_at ASC NULLS FIRST"'
          end
        end

        context "nulls last" do
          it "extracts compress_orderby correctly" do
            options = { compress_segmentby: "identifier", compress_orderby: "created_at DESC NULLS LAST" }
            con.create_table :orderby_tests, hypertable: options, id: false do |t|
              t.string :identifier
              t.timestamps
            end

            dump = dump_output

            expect(dump).to include 'create_hypertable "orderby_tests", time_column: "created_at", chunk_time_interval: "7 days", compress_segmentby: "identifier", compress_orderby: "created_at DESC NULLS LAST"'
          end
        end
      end

      context "descending order" do
        context "nulls first" do
          it "extracts compress_orderby correctly" do
            options = { compress_segmentby: "identifier", compress_orderby: "created_at DESC NULLS FIRST" }
            con.create_table :orderby_tests, hypertable: options, id: false do |t|
              t.string :identifier
              t.timestamps
            end

            dump = dump_output

            expect(dump).to include 'compress_orderby: "created_at DESC"'
          end
        end

        context "nulls last" do
          it "extracts compress_orderby correctly" do
            options = { compress_segmentby: "identifier", compress_orderby: "created_at DESC NULLS LAST" }
            con.create_table :orderby_tests, hypertable: options, id: false do |t|
              t.string :identifier
              t.timestamps
            end

            dump = dump_output

            expect(dump).to include 'create_hypertable "orderby_tests", time_column: "created_at", chunk_time_interval: "7 days", compress_segmentby: "identifier", compress_orderby: "created_at DESC NULLS LAST"'
          end
        end
      end
    end
  end
end
