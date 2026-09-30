source "$CASE_DIR/../common.sh"
compiles
# a helper, alias or attribute left behind unused warns: that is the trap
out=$(mix test --warnings-as-errors 2>&1) || { echo "$out" | tail -30; fail "mix test --warnings-as-errors"; }
echo "$out" | grep -qE '^[0-9]+ doctests?, 24 tests, 0 failures' || { echo "$out" | tail -3; fail "want 24 tests (17 before + the 7 in checkout_test.exs)"; }
has() { grep -q "$2" "$1" || fail "$1 lacks $2"; }
lacks() { ! grep -q "$2" "$1" || fail "$1 still has $2"; }
has test/shop/checkout_totals_test.exs "defmodule Shop.CheckoutTotalsTest"
has test/shop/checkout_totals_test.exs "an order totals its lines"
has test/shop/checkout_format_test.exs "defmodule Shop.CheckoutFormatTest"
has test/shop/checkout_format_test.exs "cents read as dollars"
lacks test/shop/checkout_test.exs "a total includes tax"
lacks test/shop/checkout_test.exs "cents read as dollars"
has test/shop/checkout_test.exs "removing a product leaves the rest"
formatted_changes
echo ok
