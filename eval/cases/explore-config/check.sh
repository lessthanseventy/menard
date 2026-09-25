source "$CASE_DIR/../common.sh"
[ -f ANSWER.txt ] || fail "no ANSWER.txt"
head -1 ANSWER.txt | grep -Eq '(^|[^0-9.])0?\.1\b|10 ?%' || fail "rate line: $(head -1 ANSWER.txt)"
sed -n 2p ANSWER.txt | grep -q 'config/test.exs' || fail "file line: $(sed -n 2p ANSWER.txt)"
echo ok
