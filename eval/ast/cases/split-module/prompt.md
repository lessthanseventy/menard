`lib/acme/catalog.ex` has grown to ~1,800 lines. Split it by concern into five modules, one file
each under `lib/acme/catalog/`:

- `Acme.Catalog.Products` (`products.ex`): `new_product`, `product_slug`, `product_*`, `put_product_*`
- `Acme.Catalog.Pricing` (`pricing.ex`): `*_price`, `*_price_with_tax`
- `Acme.Catalog.Inventory` (`inventory.ex`): `stock_in_*`, `restock_*`
- `Acme.Catalog.Search` (`search.ex`): `find_by_sku`, `price_range`, `search_by_*`, `count_by_*`
- `Acme.Catalog.Reviews` (`reviews.ex`): `rate_*`, `average_*`

Each function moves with its `@doc` and `@spec`, and with the private helpers, module attributes,
aliases and requires it uses. `Acme.Catalog` stays as a thin facade: every public function it has
today must still be callable on it (`defdelegate` is fine), and it keeps no other code.

Move the tests too: each `describe` block of `test/acme/catalog_test.exs` goes to
`test/acme/catalog/<concern>_test.exs` (e.g. `test/acme/catalog/pricing_test.exs`), testing the new
module directly. The storefront test may stay where it is.

The project must compile with `--warnings-as-errors`, be formatted, and its tests pass.
