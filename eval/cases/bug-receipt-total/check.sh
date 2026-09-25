source "$CASE_DIR/../common.sh"
compiles
before=$(git show HEAD:test/shop/mailer_test.exs | grep -c '^\s*test "')
after=$(grep -c '^\s*test "' test/shop/mailer_test.exs)
[ "$after" -gt "$before" ] || fail "no test added to test/shop/mailer_test.exs"
tests_pass
formatted
