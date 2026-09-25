source "$CASE_DIR/../common.sh"
compiles
grep -q 'describe "receipt file"' test/shop/mailer_test.exs || fail "no describe block"
grep -q '@tag :tmp_dir' test/shop/mailer_test.exs || fail "no @tag :tmp_dir"
# the context's tmp_dir, however it is reached: `%{tmp_dir: dir}`, `context.tmp_dir`, `ctx[:tmp_dir]`
grep -Eq '%\{[^}]*tmp_dir:|\.tmp_dir\b|\[:tmp_dir\]' test/shop/mailer_test.exs || fail "test does not use its tmp_dir"
out=$(mix test test/shop/mailer_test.exs 2>&1) || { echo "$out" | tail -20; fail "mailer tests"; }
echo "$out" | grep -Eq '3 tests, 0 failures' || fail "expected 3 tests in mailer_test: $(echo "$out" | tail -1)"
tests_pass
formatted
