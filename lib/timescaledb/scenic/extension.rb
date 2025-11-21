# Scenic does not include `WITH` option that is used with continuous aggregates.
module Timescaledb
  module Scenic
    module Extension
      # @override Scenic::Adapters::Postgres#create_materialized_view
      # Creates a materialized view in the database
      #
      # @param name The name of the materialized view to create
      # @param sql_definition The SQL schema that defines the materialized view.
      # @param with [String] Default: nil. Set with: "..." to add "WITH (...)".
      # @param no_data [Boolean] Default: false. Set to true to not create data.
      #   materialized view without running the associated query. You will need
      #   to perform a non-concurrent refresh to populate with data.
      #
      # This is typically called in a migration via {Statements#create_view}.
      # @return [void]
      def create_materialized_view(name, sql_definition, with: nil, no_data: false)
        execute <<-SQL
  CREATE MATERIALIZED VIEW #{quote_table_name(name)}
  #{"WITH (#{with})" if with} AS
  #{sql_definition.rstrip.chomp(';')}
  #{'WITH NO DATA' if no_data};
        SQL
      end

      # @override Scenic::Adapters::Postgres#create_view
      # to add the `with: ` keyword that can be used for such option.
      def create_view(name, version: nil, with: nil, sql_definition: nil, materialized: false, no_data: false)
        if version.present? && sql_definition.present?
          raise(
            ArgumentError,
            "sql_definition and version cannot both be set",
          )
        end

        if version.blank? && sql_definition.blank?
          version = 1
        end

        sql_definition ||= definition(name, version)

        if materialized
          ::Scenic.database.create_materialized_view(
            name,
            sql_definition,
            no_data: no_data,
            with: with
          )
        else
          ::Scenic.database.create_view(name, sql_definition, with: with)
        end
      end

      private

      def definition(name, version)
        ::Scenic::Definition.new(name, version).to_sql
      end
    end
    module MigrationHelpers
      # Create a timescale continuous aggregate view
      def create_scenic_continuous_aggregate(name)
        ::Scenic.database.create_view(name, materialized: true, no_data: true, with: "timescaledb.continuous")
      end
    end
  end
end


