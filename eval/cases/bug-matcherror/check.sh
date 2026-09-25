source "$CASE_DIR/../common.sh"
compiles
# a new test anywhere under test/ (not the hidden ones) counts
before=$(git ls-files test | grep -v '^test/hidden/' | xargs -I{} git show eval-base:{} | grep -cE '^\s*test "')
after=$(git ls-files -co --exclude-standard test | grep -v '^test/hidden/' | xargs cat | grep -cE '^\s*test "')
[ "$after" -gt "$before" ] || fail "no test added under test/"
tests_pass
formatted
