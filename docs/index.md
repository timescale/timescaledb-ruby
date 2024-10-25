# The TimescaleDB Ruby Gem

Welcome to the TimescaleDB gem! To experiment with the code, start installing the
gem:

## Installing

You can install the gem locally:

```bash
gem install timescaledb
```

Or require it directly in the Gemfile of your project:

```ruby
gem "timescaledb"
```

## Features

* The model can use the [acts_as_hypertable](https://github.com/timescale/timescaledb-ruby/tree/master/lib/timescaledb/acts_as_hypertable.rb) macro. Check more on [models](models) documentation.
* The ActiveRecord [migrations](migrations) can use the [create_table](https://github.com/timescale/timescaledb-ruby/tree/master/lib/timescaledb/migration_helpers.rb) supporting the `hypertable` keyword. It's also enabling you to add retention and continuous aggregates policies
* A standalone `create_hypertable` macro is also allowed in the migrations.
* Testing also becomes easier as the [schema dumper](https://github.com/timescale/timescaledb-ruby/tree/master/lib/timescaledb/schema_dumper.rb) will automatically introduce the hypertables to all environments.
* It also contains a [scenic extension](https://github.com/timescale/timescaledb-ruby/tree/master/lib/timescaledb/scenic/extension.rb) to work with [scenic views](https://github.com/scenic-views/scenic) as it's a wide adoption in the community.
* The gem is also packed with a [command line utility](command_line) that makes it easier to navigate in your database with Pry and all your hypertables available in a Ruby style.

## Examples

The [all_in_one](https://github.com/timescale/timescaledb-ruby/tree/master/examples/all_in_one/all_in_one.rb) example shows:

1. Create a hypertable with compression settings
2. Insert data
3. Run some queries
4. Check chunk size per model
5. Compress a chunk
6. Check chunk status
7. Decompress a chunk

The [ranking](https://github.com/timescale/timescaledb-ruby/tree/master/examples/ranking) example shows how to configure a Rails app and navigate all the features available.


## Toolkit  examples

There are also examples in the [toolkit-demo](https://github.com/timescale/timescaledb-ruby/tree/master/examples/toolkit-demo) folder that can help you to
understand how to properly use the toolkit functions.

* [ohlc](https://github.com/timescale/timescaledb-ruby/tree/master/examples/toolkit-demo/ohlc.rb) is a funtion that groups data by Open, High, Low, Close and make histogram availables to group the data, very useful for financial analysis.
* While building the [LTTB tutorial]( https://jonatas.github.io/timescaledb/toolkit_lttb_tutorial/) I created the [lttb](https://github.com/timescale/timescaledb-ruby/tree/master/examples/toolkit-demo/lttb) is a simple charting using the Largest Triangle Three Buckets and there. A [zoomable](https://github.com/timescale/timescaledb-ruby/tree/master/examples/toolkit-demo/lttb-zoom) version which allows to navigate in the data and zoom it keeping the same data resolution is also available.
* A small example showing how to process [volatility](https://github.com/timescale/timescaledb-ruby/blob/master/examples/toolkit-demo/compare_volatility.rb) is also good to get familiar with the pipeline functions. A benchmark implementing the same in Ruby is also available to check how it compares to the SQL implementation.


## Extra resources

If you need extra help, please join the fantastic [timescale community](https://www.timescale.com/community)
or ask your question on [StackOverflow](https://stackoverflow.com/questions/tagged/timescaledb) using the `#timescaledb` tag.

If you want to go deeper in the library, the [videos](videos) links to all
live-coding sessions showed how [@jonatasdp](https://twitter.com/jonatasdp) built the gem.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/timescale/timescaledb-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/timescale/timescaledb-ruby/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/timescale/timescaledb-ruby/blob/master/CODE_OF_CONDUCT.md).
