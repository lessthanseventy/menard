source "$CASE_DIR/../common.sh"
compiles
before=$(git show HEAD:test/shop/cart_test.exs | grep -c '^\s*test "')
after=$(grep -c '^\s*test "' test/shop/cart_test.exs)
[ "$after" -gt "$before" ] || fail "no test added to test/shop/cart_test.exs"
tests_pass
formatted
