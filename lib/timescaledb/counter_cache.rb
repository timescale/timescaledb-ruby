# frozen_string_literal: true
# Counter cache for TimescaleDB
#
# This module provides a counter cache for TimescaleDB using continuous aggregates.
# It allows you to count records over specified timeframes for belongs_to associations.
#
# Usage:
#
# class Post < ActiveRecord::Base
#   include Timescaledb::CounterCache
#   belongs_to :user, counter_cache: :timescaledb
# end
#
# class Comment < ActiveRecord::Base
#   include Timescaledb::CounterCache
#   belongs_to :post, counter_cache: :timescaledb
# end
#
# Post.belongs_to_with_counter_cache :user, counter_cache: :timescaledb
# Comment.belongs_to_with_counter_cache :post, counter_cache: :timescaledb

# By default, the counter cache will track hourly and daily counts:
#
# Post.first.comment_user_count_per_hour_total
# Post.first.comment_user_count_per_day_total
#
# Comment.first.post_post_count_per_hour_total
# Comment.first.post_post_count_per_day_total
#
# Also accessible as class methods:
# Comment::PostCountPerHourTotal
# Comment::PostCountPerDayTotal
#
# You can also specify custom timeframes:
#
# Post.belongs_to_with_counter_cache :user, counter_cache: :timescaledb, timeframes: [:month]
#
# Post.first.comment_user_count_per_month_total
#
# You can also specify a custom scope name:
#
# Post.belongs_to_with_counter_cache :user, counter_cache: :timescaledb, scope_name: :comments_count
#
# Post.first.comment_user_count_per_hour_total
# Post.first.comment_user_count_per_day_total
# Post.first.comment_user_count_per_month_total
#
# Comment.belongs_to_with_counter_cache :post, counter_cache: :timescaledb, scope_name: :posts_count
#
# Comment.first.post_post_count_per_hour_total
# Comment.first.post_post_count_per_day_total
# Comment.first.post_post_count_per_month_total
#
# You can also specify a custom foreign key:
#
# Post.belongs_to_with_counter_cache :user, counter_cache: :timescaledb, foreign_key: :user_id
module Timescaledb
  module CounterCache
    extend ActiveSupport::Concern

    included do
      class_attribute :counter_cache_options
      self.counter_cache_options ||= {}
    end

    class_methods do
      # Sets up a counter cache using TimescaleDB continuous aggregates for a belongs_to association
      # @param association_name [Symbol] The name of the belongs_to association
      # @param counter_cache [Symbol] Set to :timescaledb to enable TimescaleDB counter cache
      def belongs_to_with_counter_cache(association_name, counter_cache: nil)
        belongs_to association_name

        return unless counter_cache == :timescaledb

        self.counter_cache_options ||= {}
        self.counter_cache_options[association_name] = {
          timeframes: [:hour, :day],
          foreign_key: "#{association_name}_id"
        }
        setup_counter_aggregate(association_name)

        # Note: Continuous aggregates are refreshed via policies to avoid blocking operations
        # like record deletions. The refresh policies are set up automatically when creating
        # the continuous aggregates.
      end

      # Creates continuous aggregates for counting records over specified timeframes
      # @param association_name [Symbol] The name of the association to count
      # @param timeframes [Array<Symbol>] Array of timeframes (e.g., [:hour, :day])
      # @raise [ArgumentError] If the association or timeframes are invalid
      def setup_counter_aggregate(association_name, timeframes = nil)
        options = counter_cache_options[association_name]
        raise ArgumentError, "No counter cache options found for #{association_name}" unless options

        timeframes ||= options[:timeframes]
        scope_name = "count_by_#{self.name.demodulize.underscore}_#{association_name}"

        # Define the scope for counting
        scope scope_name, -> {
          select("count(*) as total")
          .select(options[:foreign_key])
          .group(options[:foreign_key])
        }

        # Set up continuous aggregates
        continuous_aggregates(
          scopes: [scope_name],
          timeframes: timeframes,
          materialized_only: false
        )

        # Create the continuous aggregates
        create_continuous_aggregates(materialized_only: false)

        # Add counter cache methods to the target class
        target_class = reflect_on_association(association_name).klass
        prefix = self.name.demodulize.underscore
        self_class = self
        timeframes.each do |timeframe|
          method_name = "#{association_name}_#{prefix}_count_per_#{timeframe}_total"
          target_class.define_method(method_name) do
            klass = "CountBy#{prefix.to_s.classify}#{association_name.to_s.classify}Per#{timeframe.to_s.classify}"
            self_class.const_get(klass).where(options[:foreign_key] => id).sum(:total)&.to_i || 0
          end
        end
      end
    end
  end
end
