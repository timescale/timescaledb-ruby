# frozen_string_literal: true

module Timescaledb
  module Toolkit
    module TimeVector
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def value_column
          @value_column ||= hypertable_options[:value_column] || :val
        end

        def time_column
          respond_to?(:time_column) && super || hypertable_options[:time_column]
        end

        def segment_by_column
          hypertable_options[:segment_by] || hypertable_options[:compress_segment_by]
        end

        protected

        def define_default_vector_scopes
          scope :volatility, -> (segment_by: segment_by_column, value: value_column) do
            select([*segment_by,
               "timevector(#{time_column}, #{value}) -> sort() -> delta() -> abs() -> sum() as volatility"
            ].join(", ")).group(segment_by)
          end

          scope :time_weight, -> (segment_by: segment_by_column) do
            select([*segment_by,
               "timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> time_weight() as time_weight"
            ].join(", "))
              .group(segment_by)
          end

          scope :lttb, -> (threshold:, segment_by: segment_by_column, time: time_column, value: value_column, value_exp: value_column) do
            if value =~ /(.*)\bas\b(.*)/
              value_exp = $1
              value = $2
            end
            lttb_query = <<~SQL
              WITH x AS ( #{select(*segment_by, time_column, value_exp || value).to_sql})
              SELECT #{"x.#{segment_by}," if segment_by}
                (lttb( x.#{time_column}, x.#{value}, #{threshold}) -> unnest()).*
              FROM x
              #{"GROUP BY #{segment_by}" if segment_by}
            SQL
            downsampled = unscoped
              .select(*segment_by, "time as #{time_column}, value as #{value_column}")
              .from("(#{lttb_query}) as x")
            if segment_by
              downsampled.inject({}) do |group,e|
                key = e.send(segment_by)
                (group[key] ||= []) << [e.send(time_column), e.send(value_column)]
                group
              end
            else
              downsampled.map{|e|[ e[time_column],e[value_column]]}
            end
          end


          scope :_candlestick, -> (timeframe: '1h',
                           segment_by: segment_by_column,
                           time: time_column,
                           volume: 'volume',
                           value: value_column) do

             select(  %|time_bucket('#{timeframe}', "#{time}")|,
                 *segment_by,
                "candlestick_agg(#{time}, #{value}, #{volume}) as candlestick")
              .order(1)
              .group(*(segment_by ? [1,2] : 1))
          end

          scope :candlestick, -> (timeframe: '1h',
                           segment_by: segment_by_column,
                           time: time_column,
                           volume:  'volume',
                           value: value_column) do

            raw = _candlestick(timeframe: timeframe, segment_by: segment_by, time: time, value: value,  volume: volume)
            unscoped
              .from("(#{raw.to_sql}) AS candlestick")
              .select("time_bucket",*segment_by,
               "open(candlestick),
                high(candlestick),
                low(candlestick),
                close(candlestick),
                open_time(candlestick),
                high_time(candlestick),
                low_time(candlestick),
                close_time(candlestick),
                volume(candlestick),
                vwap(candlestick)")
          end
        end
      end
    end
  end
end

