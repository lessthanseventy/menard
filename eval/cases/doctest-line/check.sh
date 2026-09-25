source "$CASE_DIR/../common.sh"
compiles
grep -Eq 'iex> Shop\.Money\.format\(-[0-9]' lib/shop/money.ex || grep -Eq 'iex> (Money\.)?format\(-[0-9]' lib/shop/money.ex || fail "no negative example"
out=$(mix test test/shop/money_test.exs 2>&1) || { echo "$out" | tail -20; fail "money tests"; }
echo "$out" | grep -Eq '2 doctests' || fail "expected 2 doctests: $(echo "$out" | tail -1)"
tests_pass
formatted
