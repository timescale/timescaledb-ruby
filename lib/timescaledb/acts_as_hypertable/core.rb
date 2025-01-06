# frozen_string_literal: true

module Timescaledb
  module ActsAsHypertable
    module Core
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def time_column
          @time_column ||= hypertable_options[:time_column] || :created_at
        end

        protected

        def define_association_scopes
          scope :chunks, -> do
            Chunk.where(hypertable_name: table_name)
          end

          scope :hypertable, -> do
            Hypertable.find_by(hypertable_name: table_name)
          end

          scope :jobs, -> do
            Job.where(hypertable_name: table_name)
          end

          scope :job_stats, -> do
            JobStats.where(hypertable_name: table_name)
          end

          scope :compression_settings, -> do
            CompressionSettings.where(hypertable_name: table_name)
          end

          scope :caggs, -> do
            ContinuousAggregates.where(hypertable_name: table_name)
          end
        end

        def define_default_scopes
          scope :between, ->(start_time, end_time) do
            where("#{time_column} BETWEEN ? AND ?", start_time, end_time)
          end

          scope :previous_month, -> do
            ref = 1.month.ago.in_time_zone
            between(ref.beginning_of_month, ref.end_of_month)
          end

          scope :previous_week, -> do
            ref = 1.week.ago.in_time_zone
            between(ref.beginning_of_week, ref.end_of_week)
          end

          scope :this_month, -> do
            ref = Time.now.in_time_zone
            between(ref.beginning_of_month, ref.end_of_month)
          end

          scope :this_week, -> do
            ref = Time.now.in_time_zone
            between(ref.beginning_of_week, ref.end_of_week)
          end

          scope :yesterday, -> do
            ref = 1.day.ago.in_time_zone
            between(ref.yesterday, ref.yesterday)
          end

          scope :today, -> do
            ref = Time.now.in_time_zone
            between(ref.beginning_of_day, ref.end_of_day)
          end

          scope :last_hour, -> { where("#{time_column} > ?", 1.hour.ago.in_time_zone) }
        end

        def normalize_hypertable_options
          hypertable_options[:time_column] = hypertable_options[:time_column].to_sym
        end
      end
    end
  end
end
