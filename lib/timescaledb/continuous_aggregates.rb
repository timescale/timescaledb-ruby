module Timescaledb
  class ContinuousAggregate < ::Timescaledb::ApplicationRecord
    self.table_name = "timescaledb_information.continuous_aggregates"
    self.primary_key = 'materialization_hypertable_name'

    has_many :jobs, foreign_key: "hypertable_name",
      class_name: "Timescaledb::Job"

    has_many :chunks, foreign_key: "hypertable_name",
      class_name: "Timescaledb::Chunk"

    scope :resume, -> do
      {
        total: count
      }
    end

    scope :hierarchical, -> do
      with_recursive = <<~SQL
        WITH RECURSIVE caggs AS (
          SELECT mat_hypertable_id, parent_mat_hypertable_id, user_view_name
            FROM _timescaledb_catalog.continuous_agg
          UNION ALL
          SELECT continuous_agg.mat_hypertable_id, continuous_agg.parent_mat_hypertable_id, continuous_agg.user_view_name
            FROM _timescaledb_catalog.continuous_agg
        JOIN caggs ON caggs.parent_mat_hypertable_id = continuous_agg.mat_hypertable_id
        )
        SELECT * FROM caggs
        ORDER BY mat_hypertable_id
      SQL
      views = unscoped
        .select("distinct user_view_name")
        .from("(#{with_recursive}) as caggs")
        .pluck(:user_view_name)
        .uniq

      views.map do |view|
        find_by(view_name: view)
      end
    end
  end
  ContinuousAggregates = ContinuousAggregate
end
