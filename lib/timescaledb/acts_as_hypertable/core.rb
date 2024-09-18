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
          scope :previous_month, -> do
            where(
              "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
              start_time: Date.today.last_month.in_time_zone.beginning_of_month.to_date,
              end_time: Date.today.last_month.in_time_zone.end_of_month.to_date
            )
          end

          scope :previous_week, -> do
            where(
              "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
              start_time: Date.today.last_week.in_time_zone.beginning_of_week.to_date,
              end_time: Date.today.last_week.in_time_zone.end_of_week.to_date
            )
          end

          scope :this_month, -> do
            where(
              "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
              start_time: Date.today.in_time_zone.beginning_of_month.to_date,
              end_time: Date.today.in_time_zone.end_of_month.to_date
            )
          end

          scope :this_week, -> do
            where(
              "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
              start_time: Date.today.in_time_zone.beginning_of_week.to_date,
              end_time: Date.today.in_time_zone.end_of_week.to_date
            )
          end

          scope :yesterday, -> { where("DATE(#{time_column}) = ?", Date.yesterday.in_time_zone.to_date) }
          scope :today, -> { where("DATE(#{time_column}) = ?", Date.today.in_time_zone.to_date) }
          scope :last_hour, -> { where("#{time_column} between ? and ?", 1.hour.ago.in_time_zone, Time.now.end_of_hour.in_time_zone) }
        end

        def normalize_hypertable_options
          hypertable_options[:time_column] = hypertable_options[:time_column].to_sym
        end
      end
    end
  end
end
