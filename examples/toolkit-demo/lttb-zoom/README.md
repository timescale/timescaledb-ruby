# LTTB examples

This folder contains an example to explore the a dynamic reloading of downsampled data.

It keeps the same amount of data and refresh the data with a higher resolution
as you keep zooming in. 
There is a [./lttb_zoomable.rb](./lttb_zoomable.rb) file is a small webserver that compares
the SQL vs Ruby implementation. It also uses the [./views](./views) folder which
contains the view with the rendering and javascript part.

You can learn more by reading the [LTTB Zoom tutorial](https://timescale.github.io/timescaledb-ruby/toolkit_lttb_zoom/).


