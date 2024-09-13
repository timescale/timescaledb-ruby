module Timescaledb
  module ContinuousAggregatesHelper
    extend ActiveSupport::Concern

    class_methods do
      def continuous_aggregates(options = {})
        @time_column = options[:time_column] || 'ts'
        @timeframes = options[:timeframes] || [:minute, :hour, :day, :week, :month, :year]
        
        scopes = options[:scopes] || []
        @aggregates = {}

        scopes.each do |scope_name|
          @aggregates[scope_name] = {
            scope_name: scope_name,
            select: nil,
            group_by: nil,
            refresh_policy: options[:refresh_policy] || {}
          }
        end

        # Allow for custom aggregate definitions to override or add to scope-based ones
        @aggregates.merge!(options[:aggregates] || {})

        define_continuous_aggregate_classes
      end

      def refresh_aggregates(timeframes = nil)
        timeframes ||= @timeframes
        @aggregates.each do |aggregate_name, _|
          timeframes.each do |timeframe|
            klass = const_get("#{aggregate_name}_per_#{timeframe}".classify)
            klass.refresh!
          end
        end
      end

      def create_continuous_aggregates(with_data: false)
        @aggregates.each do |aggregate_name, config|
          previous_timeframe = nil
          @timeframes.each do |timeframe|
            klass = const_get("#{aggregate_name}_per_#{timeframe}".classify)
            interval = "'1 #{timeframe.to_s}'"
            base_query =
              if previous_timeframe
                prev_klass = const_get("#{aggregate_name}_per_#{previous_timeframe}".classify)
                prev_klass
                  .select("time_bucket(#{interval}, #{@time_column}) as #{@time_column}, #{config[:select]}")
                  .group(1, *config[:group_by])
              else
                scope = public_send(config[:scope_name])
                select_values = scope.select_values.join(', ')
                group_values = scope.group_values

                config[:select] = select_values.gsub('count(*) as total', 'sum(total) as total')
                config[:group_by] = (2...(2 + group_values.size)).map(&:to_s).join(', ')

                self.select("time_bucket(#{interval}, #{@time_column}) as #{@time_column}, #{select_values}")
                  .group(1, *group_values)
              end

            connection.execute <<~SQL
              CREATE MATERIALIZED VIEW IF NOT EXISTS #{klass.table_name}
              WITH (timescaledb.continuous) AS
              #{base_query.to_sql}
              #{with_data ? 'WITH DATA' : 'WITH NO DATA'};
            SQL

            if (policy = klass.refresh_policy)
              connection.execute <<~SQL
                SELECT add_continuous_aggregate_policy('#{klass.table_name}',
                  start_offset => INTERVAL '#{policy[:start_offset]}',
                  end_offset =>  INTERVAL '#{policy[:end_offset]}',
                  schedule_interval => INTERVAL '#{policy[:schedule_interval]}');
              SQL
            end

            previous_timeframe = timeframe
          end
        end
      end

      private

      def define_continuous_aggregate_classes
        @aggregates.each do |aggregate_name, config|
          @timeframes.each do |timeframe|
            _table_name = "#{aggregate_name}_per_#{timeframe}"
            class_name = "#{aggregate_name}_per_#{timeframe}".classify
            const_set(class_name, Class.new(ActiveRecord::Base) do
              extend ActiveModel::Naming

              class << self
                attr_accessor :config, :timeframe
              end

              self.table_name = _table_name
              self.config = config
              self.timeframe = timeframe


              def self.refresh!
                connection.execute("CALL refresh_continuous_aggregate('#{table_name}', null, null);")
              end

              def readonly?
                true
              end

              def self.refresh_policy
                config[:refresh_policy]&.dig(timeframe)
              end
            end)
          end
        end
      end
    end
  end
end
