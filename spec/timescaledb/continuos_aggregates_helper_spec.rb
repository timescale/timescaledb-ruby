require 'spec_helper'

class Download < ActiveRecord::Base
  include Timescaledb::ContinuousAggregatesHelper

  acts_as_hypertable time_column: 'ts'

  scope :total_downloads, -> { select("count(*) as total") }
  scope :downloads_by_gem, -> { select("gem_name, count(*) as total").group(:gem_name) }
  scope :downloads_by_version, -> { select("gem_name, gem_version, count(*) as total").group(:gem_name, :gem_version) }

  continuous_aggregates(
    time_column: 'ts',
    timeframes: [:minute, :hour, :day, :month],
    scopes: [:total_downloads, :downloads_by_gem, :downloads_by_version],
    refresh_policy: {
      minute: { start_offset: "10 minutes", end_offset: "1 minute", schedule_interval: "1 minute" },
      hour:   { start_offset: "4 hour",     end_offset: "1 hour",   schedule_interval: "1 hour" },
      day:    { start_offset: "3 day",      end_offset: "1 day",    schedule_interval: "1 hour" },
      month:  { start_offset: "3 month",    end_offset: "1 hour",   schedule_interval: "1 hour" }
    }
  )
end

RSpec.describe Timescaledb::ContinuousAggregatesHelper do
  let(:test_class) do
    Download
  end

  before(:all) do
    ActiveRecord::Base.connection.instance_exec do
      hypertable_options = {
        time_column: 'ts',
        chunk_time_interval: '1 day',
        compress_segmentby: 'gem_name, gem_version',
        compress_orderby: 'ts DESC',
      }
      create_table(:downloads, id: false, hypertable: hypertable_options) do |t|
        t.timestamptz :ts, null: false
        t.text :gem_name, :gem_version, null: false
        t.jsonb :payload
      end
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table :downloads, if_exists: true
  end

  describe '.continuous_aggregates' do
    it 'defines aggregate classes' do
      expect(test_class.const_defined?(:TotalDownloadsPerMinute)).to be true
      expect(test_class.const_defined?(:TotalDownloadsPerHour)).to be true
      expect(test_class.const_defined?(:TotalDownloadsPerDay)).to be true
      expect(test_class.const_defined?(:TotalDownloadsPerMonth)).to be true

      expect(test_class.const_defined?(:DownloadsByVersionPerMinute)).to be true
      expect(test_class.const_defined?(:DownloadsByVersionPerHour)).to be true
      expect(test_class.const_defined?(:DownloadsByVersionPerDay)).to be true
      expect(test_class.const_defined?(:DownloadsByVersionPerMonth)).to be true

      expect(test_class.const_defined?(:DownloadsByGemPerMinute)).to be true
      expect(test_class.const_defined?(:DownloadsByGemPerHour)).to be true
      expect(test_class.const_defined?(:DownloadsByGemPerDay)).to be true
      expect(test_class.const_defined?(:DownloadsByGemPerMonth)).to be true
    end

    it 'sets up correct table names for aggregates' do
      expect(test_class::TotalDownloadsPerMinute.table_name).to eq('total_downloads_per_minute')
      expect(test_class::TotalDownloadsPerHour.table_name).to eq('total_downloads_per_hour')
      expect(test_class::TotalDownloadsPerDay.table_name).to eq('total_downloads_per_day')
      expect(test_class::TotalDownloadsPerMonth.table_name).to eq('total_downloads_per_month')

      expect(test_class::DownloadsByVersionPerMinute.table_name).to eq('downloads_by_version_per_minute')
      expect(test_class::DownloadsByVersionPerHour.table_name).to eq('downloads_by_version_per_hour')
      expect(test_class::DownloadsByVersionPerDay.table_name).to eq('downloads_by_version_per_day')
      expect(test_class::DownloadsByVersionPerMonth.table_name).to eq('downloads_by_version_per_month')

      expect(test_class::DownloadsByGemPerMinute.table_name).to eq('downloads_by_gem_per_minute')
      expect(test_class::DownloadsByGemPerHour.table_name).to eq('downloads_by_gem_per_hour')
      expect(test_class::DownloadsByGemPerDay.table_name).to eq('downloads_by_gem_per_day')
      expect(test_class::DownloadsByGemPerMonth.table_name).to eq('downloads_by_gem_per_month')
    end

    it 'defines rollup scope for aggregates' do
      test_class.create_continuous_aggregates
      aggregate_classes = [test_class::TotalDownloadsPerMinute, test_class::TotalDownloadsPerHour, test_class::TotalDownloadsPerDay, test_class::TotalDownloadsPerMonth]
      aggregate_classes.each do |agg_class|
        expect(agg_class).to respond_to(:rollup)
        expect(agg_class.rollup.to_sql).to include('time_bucket')
        expect(agg_class.rollup.to_sql).to include('count(*) as total')
      end
    end

    it 'defines time-based scopes for aggregates' do
      aggregate_classes = [test_class::TotalDownloadsPerMinute, test_class::TotalDownloadsPerHour, test_class::TotalDownloadsPerDay, test_class::TotalDownloadsPerMonth]
      aggregate_scopes = [:total_downloads, :downloads_by_gem, :downloads_by_version]
      
      aggregate_scopes.each do |scope|
        aggregate_classes.each do |agg_class|
          expect(agg_class).to respond_to(scope)
        end
      end
    end
  end

  describe '.create_continuous_aggregates' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
    end

    it 'creates materialized views for each aggregate' do
      test_class.create_continuous_aggregates

      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/CREATE MATERIALIZED VIEW.*downloads_total_downloads_per_minute/i)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/CREATE MATERIALIZED VIEW.*downloads_total_downloads_per_hour/i)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/CREATE MATERIALIZED VIEW.*downloads_total_downloads_per_day/i)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/CREATE MATERIALIZED VIEW.*downloads_total_downloads_per_month/i)
    end

    it 'sets up refresh policies for each aggregate' do
      test_class.create_continuous_aggregates

      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/add_continuous_aggregate_policy.*downloads_minutely/i)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/add_continuous_aggregate_policy.*downloads_total_downloads_per_hour/i)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/add_continuous_aggregate_policy.*downloads_total_downloads_per_day/i)
      expect(ActiveRecord::Base.connection).to have_received(:execute).with(/add_continuous_aggregate_policy.*downloads_total_downloads_per_month/i)
    end
  end

  describe 'refresh policies' do
    it 'defines appropriate refresh policies for each timeframe' do
      policies = {
        minute: { start_offset: "INTERVAL '10 minutes'", end_offset: "INTERVAL '1 minute'", schedule_interval: "INTERVAL '1 minute'" },
        hour:   { start_offset: "INTERVAL '4 hour'",     end_offset: "INTERVAL '1 hour'",   schedule_interval: "INTERVAL '1 hour'" },
        day:    { start_offset: "INTERVAL '3 day'",      end_offset: "INTERVAL '1 day'",    schedule_interval: "INTERVAL '1 day'" },
        month:  { start_offset: "INTERVAL '3 month'",    end_offset: "INTERVAL '1 day'",  schedule_interval: "INTERVAL '1 day'" } 
      }

      policies.each do |timeframe, expected_policy|
        actual_policy = test_class.const_get(timeframe).refresh_policy
        expect(actual_policy).to eq(expected_policy)
      end
    end
  end
end
