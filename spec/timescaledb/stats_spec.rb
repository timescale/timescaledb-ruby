RSpec.describe Timescaledb::Stats do
  let(:hypertables) { Timescaledb::Hypertable.all }

  subject(:stats) { described_class.new(hypertables) }

  describe '.to_h' do
    it 'returns expected structure' do
      approximate_row_count = hypertables.each_with_object(Hash.new) do |hypertable, count|
        name = [hypertable.hypertable_schema, hypertable.hypertable_name].join('.')

        count[name] = a_kind_of(Integer)
      end

      expect(subject.to_h).to match(
        a_hash_including(
          continuous_aggregates: { total: a_kind_of(Integer) },
          hypertables: {
            approximate_row_count: approximate_row_count,
            chunks: { compressed: a_kind_of(Integer), total: a_kind_of(Integer), uncompressed: a_kind_of(Integer) },
            count: hypertables.count,
            size: {
              compressed: a_kind_of(String),
              uncompressed: a_kind_of(String)
            },
            uncompressed_count: a_kind_of(Integer)
          },
          jobs_stats: {
            failures: a_kind_of(Integer), runs: a_kind_of(Integer), success: a_kind_of(Integer)
          }
        )
      )
    end
  end
end