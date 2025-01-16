# LTTB examples

This folder contains a few ideas to explore and learn more about the lttb algorithm.

There is a [./lttb.rb](./lttb.rb) file that is the Ruby implementation of lttb
and also contains the related [./lttb_test.rb](./lttb_test.rb) file that
verifies the same example from the Timescale Toolkit [implementation](https://github.com/timescale/timescaledb-toolkit/blob/6ee2ea1e8ff64bab10b90bdf4cd4b0f7ed763934/extension/src/lttb.rs#L512-L530).

The [./lttb_sinatra.rb](./lttb_sinatra.rb) is a small webserver that compares
the SQL vs Ruby implementation. It also uses the [./views](./views) folder which
contains the view rendering part.

You can learn more by reading the [LTTB tutorial](https://timescale.github.io/timescaledb-ruby/toolkit_lttb_tutorial/).


