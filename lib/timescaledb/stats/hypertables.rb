require_relative './chunks'
require 'active_support/core_ext/module/delegation'

module Timescaledb
  class Stats
    class Hypertables
      # @param [Timescaledb:Connection] connection The PG connection.
      # @param [Array<String>] hypertables The list of hypertable names.
      def initialize(hypertables = [], connection = Timescaledb.connection)
        @connection = connection
        @hypertables = hypertables.map(&method('hypertable_name_with_schema'))
      end

      delegate :query, :query_first, :query_count, to: :@connection

      # @return [Hash] The hypertables stats
      def to_h
        {
          count: @hypertables.count,
          uncompressed_count: uncompressed_count,
          approximate_row_count: approximate_row_count,
          chunks: Timescaledb::Stats::Chunks.new(@hypertables).to_h,
          size: size
        }
      end

      private

      def uncompressed_count
        @hypertables.count do |hypertable|
          query("SELECT * from hypertable_compression_stats('#{hypertable}')").empty?
        end
      end

      def approximate_row_count
        @hypertables.each_with_object(Hash.new) do |hypertable, summary|
          row_count = query_first("SELECT * FROM approximate_row_count('#{hypertable}')").approximate_row_count.to_i

          summary[hypertable] = row_count
        end
      end

      def size
        sum = -> (method_name) { (@hypertables.map(&method(method_name)).inject(:+) || 0) }

        {
          uncompressed: humanize_bytes(sum[:before_total_bytes]),
          compressed: humanize_bytes(sum[:after_total_bytes])
        }
      end

      def before_total_bytes(hypertable)
        (compression_stats[hypertable]&.before_compression_total_bytes || detailed_size[hypertable]).to_i
      end

      def after_total_bytes(hypertable)
        (compression_stats[hypertable]&.after_compression_total_bytes || 0).to_i
      end

      def compression_stats
        @compression_stats ||=
          @hypertables.each_with_object(Hash.new) do |hypertable, stats|
            stats[hypertable] = query_first(compression_stats_query, [hypertable])
            stats
          end
      end

      def compression_stats_query
        'SELECT * FROM hypertable_compression_stats($1)'
      end

      def detailed_size
        @detailed_size ||=
          @hypertables.each_with_object(Hash.new) do |hypertable, size|
            size[hypertable] = query_first(detailed_size_query, [hypertable]).total_bytes
            size
          end
      end

      def detailed_size_query
        'SELECT * FROM hypertable_detailed_size($1)'
      end

      def hypertable_name_with_schema(hypertable)
        if hypertable.is_a?(String)
          hypertable
        else
          [hypertable.hypertable_schema, hypertable.hypertable_name].compact.join('.')
        end
      end

      def humanize_bytes(bytes)
        units = %w(B KiB MiB GiB TiB PiB EiB)

        return '0 B' if bytes == 0

        exp = (Math.log2(bytes) / 10).floor
        max_exp = units.size - 1
        exp = max_exp if exp > max_exp

        value = (bytes.to_f / (1 << (exp * 10))).round(1)

        "#{value} #{units[exp]}"
      end
    end
  end
end