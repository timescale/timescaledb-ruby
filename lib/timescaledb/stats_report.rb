require "active_support/core_ext/numeric/conversions"

module Timescaledb
  module StatsReport
    module_function
    def resume(scope=Hypertable.all)
      base_filter = {hypertable_name: scope.pluck(:hypertable_name)}
      {
        hypertables: {
          count: scope.count,
          uncompressed: scope.to_a.count { |h| h.compression_stats.empty? },
          approximate_row_count: approximate_row_count(scope),
          chunks: Chunk.where(base_filter).resume,
          size: compression_resume(scope)
        },
        continuous_aggregates: ContinuousAggregates.where(base_filter).resume,
        jobs_stats: JobStats.where(base_filter).resume
      }
    end

    def compression_resume(scope)
      sum = -> (method) { (scope.map(&method).inject(:+) || 0).to_s }
      {
        uncompressed: sum[:before_total_bytes],
        compressed: sum[:after_total_bytes]
      }
    end

    def approximate_row_count(scope)
      scope.to_a.map do |hypertable|
        { hypertable.hypertable_name => hypertable.approximate_row_count }
      end.inject(&:merge!)
    end
  end
end
