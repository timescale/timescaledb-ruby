ActiveSupport.on_load(:active_record) { extend Timescaledb::ActsAsHypertable }


class Event < ActiveRecord::Base
  acts_as_hypertable
end

class HypertableWithNoOptions < ActiveRecord::Base
  acts_as_hypertable
end

class HypertableWithOptions < ActiveRecord::Base
  acts_as_hypertable time_column: :timestamp
end

class HypertableWithCustomTimeColumn < ActiveRecord::Base
  self.table_name = "hypertable_with_custom_time_column"

  acts_as_hypertable time_column: :timestamp
end

class HypertableSkipAllScopes < ActiveRecord::Base
  self.table_name = "hypertable_skipping_all_scopes"
  acts_as_hypertable time_column: :timestamp, skip_association_scopes: true, skip_default_scopes: true
end

class HypertableWithContinuousAggregates < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  include Timescaledb::ContinuousAggregatesHelper

  acts_as_hypertable time_column: 'ts',
                     segment_by: :identifier,
                     value_column: "cast(payload->>'price' as float)"

  scope :total, -> { select("count(*) as total") }
  scope :by_identifier, -> { select("identifier, count(*) as total").group(:identifier) }
  scope :by_version, -> { select("identifier, version, count(*) as total").group(:identifier, :version) }
  scope :purchase, -> { where("identifier = 'purchase'") }
  scope :purchase_stats, -> { select("stats_agg(#{value_column}) as stats_agg").purchase }

  continuous_aggregates(
    time_column: 'ts',
    timeframes: [:minute, :hour, :day, :month],
    scopes: [:total, :by_identifier, :by_version, :purchase_stats],
    refresh_policy: {
      minute: { start_offset: "10 minutes", end_offset: "1 minute", schedule_interval: "1 minute" },
      hour:   { start_offset: "4 hour",     end_offset: "1 hour",   schedule_interval: "1 hour" },
      day:    { start_offset: "3 day",      end_offset: "1 day",    schedule_interval: "1 hour" },
      month:  { start_offset: "3 month",    end_offset: "1 hour",   schedule_interval: "1 hour" }
    }
  )
  descendants.each do |cagg|
    cagg.hypertable_options = hypertable_options.merge(value_column: :total)
    cagg.scope :stats, -> { select("average(stats_agg), stddev(stats_agg)") }
  end
end

class NonHypertable < ActiveRecord::Base
end
