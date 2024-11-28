require 'ostruct'

RSpec.describe Timescaledb do
  describe '.establish_connection' do
    it 'returns a PG::Connection object' do
      expect do
         Timescaledb.establish_connection(ENV['PG_URI_TEST'])
      end.to_not raise_error
    end
  end

  describe ::Timescaledb::Connection do
    subject(:connection) { Timescaledb::Connection.instance }

    it 'returns a Connection object' do
      is_expected.to be_a(Timescaledb::Connection)
    end

    it 'has fast access to the connection' do
      expect(connection.send(:connection)).to be_a(PG::Connection)
    end

    describe '#connected?' do
      it {  expect(connection.connected?).to be_truthy }
    end

    describe '#query_first' do
      let(:sql) { "select 1 as one" }
      subject(:result) { connection.query_first(sql) }

      it { expect(result).to be_a(OpenStruct) }
    end

    describe '#query' do
      let(:sql) { "select 1 as one" }
      subject(:result) { connection.query(sql) }

      it { expect(result).to eq([OpenStruct.new({"one" => "1"})]) }
    end
  end
end
