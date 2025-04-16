require 'active_support/core_ext/module/delegation'

module Timescaledb
  class Stats
    class Chunks
      # @param [Array<String>] hypertables The list of hypertable names.
      # @param [Timescaledb:Connection] connection The PG connection.
      def initialize(hypertables = [], connection = Timescaledb.connection)
        @connection = connection
        @hypertables = hypertables
      end

      delegate :query_count, to: :@connection

      # @return [Hash] The chunks stats
      def to_h
        { total: total, compressed: compressed, uncompressed: uncompressed }
      end

      private

      def total
        query_count(base_query, [@hypertables])
      end

      def compressed
        compressed_query = [base_query, 'is_compressed'].join(' AND ')

        query_count(compressed_query, [@hypertables])
      end

      def uncompressed
        uncompressed_query = [base_query, 'NOT is_compressed'].join(' AND ')

        query_count(uncompressed_query, [@hypertables])
      end

      def base_query
        "SELECT COUNT(1) FROM timescaledb_information.chunks WHERE hypertable_name IN ($1)"
      end
    end
  end
end