sed -i 's/plugins: \[Phoenix.LiveView.HTMLFormatter\]/plugins: [Styler, Phoenix.LiveView.HTMLFormatter]/' .formatter.exs
mix format >/dev/null 2>&1
