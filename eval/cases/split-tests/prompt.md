test/shop/checkout_test.exs covers too much. Move its `describe "totals"` tests into a new
test/shop/checkout_totals_test.exs (module `Shop.CheckoutTotalsTest`) and its `describe "formatting"`
tests into a new test/shop/checkout_format_test.exs (module `Shop.CheckoutFormatTest`). The other
tests stay where they are. Every test must still pass, and the test files must compile without
warnings.
