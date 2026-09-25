import Config

config :shop,
  currency: "USD",
  tax_rate: 0.08,
  free_shipping_over: 5_000

config :shop, Shop.Mailer, from: "orders@shop.test"

import_config "#{config_env()}.exs"
