source "$CASE_DIR/../common.sh"
compiles
grep -Eq 'alias Shop\.(Product|\{[^}]*Product)' lib/shop_web/live/cart_live.ex || fail "no alias for Shop.Product"
grep -q 'Shop\.Product{' lib/shop_web/live/cart_live.ex && fail "still %Shop.Product{"
tests_pass
formatted
