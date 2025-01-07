# frozen_string_literal: true

module Timescaledb
  # If you want your model to hook into its underlying hypertable
  # as well as have access to TimescaleDB specific data, methods, and more,
  # specify this macro in your model.
  #
  # @note Your model's table needs to have already been converted to a hypertable
  # via the TimescaleDB `create_hypertable` function for this to work.
  #
  # @see https://docs.timescale.com/api/latest/hypertable/create_hypertable/ for
  #   how to use the SQL `create_hypertable` function.
  # @see Timescaledb::MigrationHelpers#create_table for how to create a new hypertable
  # via a Rails migration utilizing the standard `create_table` method.
  #
  # @example Enabling the macro on your model
  #   class Event < ActiveRecord::Base
  #     acts_as_hypertable
  #   end
  #
  # @see Timescaledb::ActsAsHypertable#acts_as_hypertable
  #   for configuration options
  module ActsAsHypertable
    DEFAULT_OPTIONS = {
      time_column: :created_at,
    }.freeze

    def acts_as_hypertable?
      included_modules.include?(Timescaledb::ActsAsHypertable::Core)
    end

    # == Configuration options
    #
    # @param [Hash] options The options to initialize your macro with.
    # @option options [Symbol] :time_column The name of the column in your
    #   model's table containing time values. The name provided should be
    #   the same name as the `time_column_name` you passed to the
    #   TimescaleDB `create_hypertable` function.
    #
    # @example Enabling the macro on your model with options
    #   class Event < ActiveRecord::Base
    #     acts_as_hypertable time_column: :timestamp
    #   end
    #
    # @param [Hash] options The options to initialize your macro with.
    # @option options [Boolean] :skip_association_scopes to avoid `.hypertable`, `.chunks` and other scopes related to metadata.
    # @option options [Boolean] :skip_default_scopes to avoid the generation of default time related scopes like `last_hour`, `last_week`, `yesterday` and so on...
    # @option options [Boolean] :skip_time_vector to avoid the generation of time vector related scopes
    def acts_as_hypertable(options = {})
      return if acts_as_hypertable?

      include Timescaledb::ActsAsHypertable::Core
      include Timescaledb::Toolkit::TimeVector

      class_attribute :hypertable_options, instance_writer: false

      self.hypertable_options = DEFAULT_OPTIONS.dup
      hypertable_options.merge!(options)
      normalize_hypertable_options

      define_association_scopes unless options[:skip_association_scopes]
      define_default_scopes unless options[:skip_default_scopes]
      define_default_vector_scopes unless options[:skip_time_vector]
    end
  end
end

