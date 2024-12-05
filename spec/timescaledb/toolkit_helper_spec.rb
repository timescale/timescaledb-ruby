RSpec.describe Timescaledb::Toolkit::Helpers, database_cleaner_strategy: :truncation do
  let(:con) { ActiveRecord::Base.connection }


  let(:hypertable_options) do
    {
      time_column: 'ts',
      chunk_time_interval: '1 day',
      compress_segmentby: 'device_id',
      compress_orderby: 'ts',
      compress_after: '7 days'
    }
  end

  describe "add_toolkit_to_search_path!" do
    it "adds toolkit_experimental to search path" do
      expect do
        con.add_toolkit_to_search_path!
      end.to change(con, :schema_search_path)
        .from('"$user", public')
        .to('"$user", public, toolkit_experimental')
    end
  end

  describe "pipeline functions" do
    before(:each) do
      con.add_toolkit_to_search_path!
      if con.table_exists?(:measurements)
        # We need to truncate to avoid foreign key constraint errors + deadlocks
        con.execute("TRUNCATE measurements CASCADE")
        con.execute("DROP TABLE IF EXISTS measurements CASCADE")
      end
      con.create_table :measurements, hypertable: hypertable_options, id: false do |t|
        t.integer :device_id
        t.decimal :val
        t.timestamp :ts
      end
    end

    let(:model) do
      Measurement = Class.new(ActiveRecord::Base) do
        extend Timescaledb::ActsAsHypertable
        extend Timescaledb::ActsAsTimeVector
        self.table_name = 'measurements'
        self.primary_key = nil

        acts_as_hypertable time_column: "ts"

        acts_as_time_vector segment_by: "device_id",
          value_column: "val",
          time_column: "ts"
      end
    end

    let(:yesterday) { 1.day.ago }

    before do
      [1,2,3].each_with_index do |v,i|
        model.create(device_id: 1, ts: yesterday + i.hour, val: v)
      end
    end

    describe "#volatility" do
      let(:plain_volatility_query) do
        model.select(<<~SQL).group("device_id")
        device_id, timevector(ts, val) -> sort() -> delta() -> abs() -> sum() as volatility
        SQL
      end

      it "works with plain sql"do
        expect(plain_volatility_query.first.volatility).to eq(2)
      end

      it { expect(model.value_column).to eq("val") }
      it { expect(model.time_column).to eq(:ts) }

      context "with columns specified in the volatility scope" do
        let(:query) do
          model.volatility(segment_by: "device_id")
        end
        it "segment by the param in the volatility"do
          expect(query.to_sql).to eq(plain_volatility_query.to_sql.tr("\n", ""))
        end
      end

      context "without columns" do
        let(:query) do
          model.volatility
        end
        it "uses the default segment_by_column"do
          expect(query.to_sql).to eq(plain_volatility_query.to_sql.tr("\n", ""))
        end
      end

      context "several devices" do
        before :each do
          [1,2,3].each_with_index do |v,i|
            model.create(device_id: 2, ts: yesterday + i.hour, val: v+i)
            model.create(device_id: 3, ts: yesterday + i.hour, val: i * i)
          end
        end

        # Dataset example now
        ##  model.all.order(:device_id, :ts).map(&:attributes)
        #=> [
        #     {"device_id"=>1, "val"=>1.0, "ts"=>...},
        #     {"device_id"=>1, "val"=>2.0, "ts"=>...},
        #     {"device_id"=>1, "val"=>3.0, "ts"=>...},
        #     {"device_id"=>2, "val"=>1.0, "ts"=>...},
        #     {"device_id"=>2, "val"=>3.0, "ts"=>...},
        #     {"device_id"=>2, "val"=>5.0, "ts"=>...},
        #     {"device_id"=>3, "val"=>0.0, "ts"=>...},
        #     {"device_id"=>3, "val"=>1.0, "ts"=>...},
        #     {"device_id"=>3, "val"=>4.0, "ts"=>...}]

        let(:volatility_query_for_all) do
          model.volatility(segment_by: nil)
        end
        let(:volatility_query_for_every_device) do
          model.order("device_id")
            .volatility(segment_by: "device_id")
        end

        specify do
          expect(volatility_query_for_all.map(&:attributes)).to eq([
            {"volatility"=>11.0}])

          expect(volatility_query_for_every_device.map(&:attributes)).to eq([
            {"device_id"=>1, "volatility"=>2.0},
            {"device_id"=>2, "volatility"=>4.0},
            {"device_id"=>3, "volatility"=>4.0}])
        end
      end
    end
    describe "interpolate and backfill" do
      before do
         model.create(device_id: 1, ts: yesterday + 4.hour, val: 5)
         model.create(device_id: 1, ts: yesterday + 6.hour, val: 7)
         model.create(device_id: 1, ts: yesterday + 8.hour, val: 9)
      end
      specify do
        res = model.select(<<SQL).group("hour, device_id").order("hour")
          time_bucket_gapfill('1 hour', ts,
             now() - INTERVAL '24 hours',
             now() - INTERVAL '16 hours') AS hour,
          device_id,
          avg(val) AS value,
          interpolate(avg(val))
SQL

        expect(res.map{|e|[e["value"]&.to_f,e["interpolate"]]}).to eq([
          [1.0, 1.0],
          [2.0, 2.0],
          [3.0, 3.0],
          [nil, 4.0],
          [5.0, 5.0],
          [nil, 6.0],
          [7.0, 7.0],
          [nil, 8.0],
          [9.0, 9.0]])
      end
    end
    describe "stats_aggs" do
      let(:query) do
        model.select(<<~SQL).group(1)
          time_bucket('1 h'::interval, ts) as bucket,
          stats_agg(val) as stats
        SQL
      end
      let(:options) { { with_data: true } }
      before(:each) { con.create_continuous_aggregates('measurements_stats', query, **options) }
      after(:each) { con.drop_continuous_aggregates('measurements_stats') rescue nil }
      let(:view) do
        con.execute(<<~SQL)
        SELECT
        bucket,
          average(rolling(stats) OVER (ORDER BY bucket RANGE '#{preceeding_range}' PRECEDING)),
          stddev(rolling(stats) OVER (ORDER BY bucket RANGE '#{preceeding_range}' PRECEDING))
        FROM measurements_stats;
        SQL
      end

      context 'when one hour preceeding' do
        let(:preceeding_range) { '1 hour' }
        specify do
          expect(view.map{|e|e["average"]}).to eq([1,1.5,2.5])
        end
      end

      context 'when two hour preceeding' do
        let(:preceeding_range) { '2 hours' }
        specify do
          expect(view.map{|e|e["average"]}).to eq([1,1.5,2.0])
        end
      end
    end
  end
  describe 'lttb' do
    before(:each) do
      con.add_toolkit_to_search_path!
      if con.table_exists?(:measurements)
        con.execute("TRUNCATE measurements CASCADE")
        con.execute("DROP TABLE IF EXISTS measurements CASCADE")
      end
      con.create_table :measurements, hypertable: hypertable_options, id: false do |t|
        t.integer :device_id
        t.decimal :val
        t.timestamp :ts
      end
    end

    let(:model) do
      Measurement = Class.new(ActiveRecord::Base) do
        extend Timescaledb::ActsAsHypertable
        extend Timescaledb::ActsAsTimeVector
        self.table_name = 'measurements'
        self.primary_key = nil

        acts_as_hypertable time_column: "ts"

        acts_as_time_vector segment_by: "device_id",
          value_column: "val",
          time_column: "ts"
      end
    end

    before do
      [['2020-1-1', 10],
       ['2020-1-2', 21],
       ['2020-1-3', 19],
       ['2020-1-4', 32],
       ['2020-1-5', 12],
       ['2020-1-6', 14],
       ['2020-1-7', 18],
       ['2020-1-8', 29],
       ['2020-1-9', 23],
       ['2020-1-10', 27],
       ['2020-1-11', 14]].each do |row|
        time= Time.mktime(*row[0].split('-'))
        model.create(device_id: 1, ts: time, val: row[1])
      end
    end

    context 'when segment_by is nil' do
      it 'downsample as an array' do
        downsampled = model.lttb(threshold: 5, segment_by: nil)
        data = downsampled.map do |result|
          time, value = result
          [time.to_date.to_s, value.to_i]
        end

        expect(data.size).to eq(5)
        expect(data).to eq([
          ["2020-01-01", 10],
          ["2020-01-04", 32],
          ["2020-01-05", 12],
          ["2020-01-08", 29],
          ["2020-01-11", 14]])
      end
    end
    context 'when segment_by is a column' do
      it 'downsample as a hash' do
        downsampled = model.lttb(threshold: 5, segment_by: "device_id")
        key = downsampled.keys.first
        data = downsampled[key].map do |result|
          time, value = result
          [time.to_date.to_s, value.to_i]
        end

        expect(data.size).to eq(5)
        expect(data).to eq([
          ["2020-01-01", 10],
          ["2020-01-04", 32],
          ["2020-01-05", 12],
          ["2020-01-08", 29],
          ["2020-01-11", 14]])
      end
    end
  end

  describe 'candlestick' do
    before(:each) do
      con.add_toolkit_to_search_path!
      if con.table_exists?(:ticks)
        con.execute("TRUNCATE ticks CASCADE")
        con.execute("DROP TABLE IF EXISTS ticks CASCADE")
      end
      con.create_table :ticks, hypertable: hypertable_options, id: false do |t|
        t.text :symbol
        t.decimal :price
        t.decimal :volume
        t.timestamp :time
      end
    end

    let(:hypertable_options) do
      {
        time_column: 'time',
        chunk_time_interval: '1 month',
        compress_segmentby: 'symbol',
        compress_orderby: 'time'
      }
    end

    let(:model) do
      Tick = Class.new(ActiveRecord::Base) do
        extend Timescaledb::ActsAsTimeVector
        extend Timescaledb::ActsAsHypertable
        self.table_name = 'ticks'
        self.primary_key = nil

        acts_as_hypertable time_column: "time"

        acts_as_time_vector segment_by: "symbol",
          value_column: "price",
          time_column: "time"
      end
    end

    before do
      [['2020-1-2', 10],
       ['2020-1-3', 13],
       ['2020-1-4', 9],
       ['2020-1-5', 12]].each do |row|
         time= Time.utc(*row[0].split('-'))
        model.create(time: time, price: row[1], symbol: "FIRST")
      end
    end

    context "when call ohlc without segment_by" do
      let(:ohlcs) do
        model.where(symbol: "FIRST").candlestick(timeframe: '1w', segment_by: nil)
      end

      it "process open, high, low, close" do
        expect(ohlcs.size).to eq(1)

        ohlc = ohlcs.first.attributes

        expect(ohlc.slice(*%w[open high low close]))
          .to eq({"open"=>10.0, "high"=>13.0, "low"=>9.0, "close"=>12.0})

        expect(ohlc.slice(*%w[open_time high_time low_time close_time]).transform_values(&:day))
          .to eq({"open_time"=>2, "high_time"=>3, "low_time"=>4, "close_time"=>5})
      end
    end

    context "when call ohlc wth segment_by symbol" do
      before do
        [['2020-1-2', 20],
         ['2020-1-3', 23],
         ['2020-1-4', 19],
         ['2020-1-5', 14]].each do |row|
           time= Time.utc(*row[0].split('-'))
           model.create(time: time, price: row[1], symbol: "SECOND")
         end
      end

      let!(:ohlcs) do
        model.candlestick(timeframe: '1w', segment_by: :symbol)
      end

      it "process open, high, low, close" do
        expect(ohlcs.size).to eq(2)
        data = ohlcs.group_by(&:symbol).transform_values{|v|v.first.attributes}

        first = data["FIRST"]
        second = data["SECOND"]

        expect(first.slice(*%w[open high low close]))
          .to eq({"open"=>10.0, "high"=>13.0, "low"=>9.0, "close"=>12.0})

        expect(second.slice(*%w[open high low close]))
          .to eq({"open"=>20.0, "high"=>23.0, "low"=>14.0, "close"=>14.0})

        expect(first.slice(*%w[open_time high_time low_time close_time]).transform_values(&:day))
          .to eq({"open_time"=>2, "high_time"=>3, "low_time"=>4, "close_time"=>5})

        expect(second.slice(*%w[open_time high_time low_time close_time]).transform_values(&:day))
          .to eq({"open_time"=>2, "high_time"=>3, "low_time"=>5, "close_time"=>5})
      end
    end
  end
end
