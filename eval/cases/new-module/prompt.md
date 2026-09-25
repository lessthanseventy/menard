Add a `Shop.Discounts` module with `apply_code(cents, code)`: "TENOFF" takes 10% off (rounding
down to the cent), "FIVE" takes 500 cents off but never goes below 0, and both return
`{:ok, cents}`; any other code returns `{:error, :unknown_code}`. Add tests in
test/shop/discounts_test.exs.
