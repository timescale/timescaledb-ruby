# Changelog

Here you can find the changes to the project that may be relevant to you.

# 2025-01-06

* For the `create_hypertable` method, the param `compression_interval` is now renamed to `compress_after` just to make it more consistent with the other parameters.
* Change examples to use `drop_table t, if_exists: true` (#85) - Thanks @intermittentnrg

# 2024-12-21

Note that the gem is not overloaded automatically, you'll need to add the following line to your `config/application.rb` file:

```ruby
ActiveSupport.on_load(:active_record) { extend Timescaledb::ActsAsHypertable }
```

Or create a hypertable model which inherits from `ApplicationRecord` or your custom base class:

```ruby
class Hypertable < ApplicationRecord
  extend Timescaledb::ActsAsHypertable

  self.abstract_class = true
end
```
