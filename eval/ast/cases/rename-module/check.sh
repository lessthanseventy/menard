# Acme.Billing is Acme.Invoicing everywhere, file and test moved; what only shares its name
# (Acme.BillingAddress, Acme.Reports.Billing and the calls through its `Billing` alias, the stored
# "Acme.Billing" string) is on as many lines as at eval-base; compiles clean, the suite and the
# hidden test pass.
source "$EVAL_COMMON"
[ -f lib/acme/invoicing.ex ] || fail "lib/acme/invoicing.ex missing"
[ ! -e lib/acme/billing.ex ] || fail "lib/acme/billing.ex still there"
[ -f test/acme/invoicing_test.exs ] || fail "test/acme/invoicing_test.exs missing"
[ ! -e test/acme/billing_test.exs ] || fail "test/acme/billing_test.exs still there"
left=$(grep -rnE 'Acme\.Billing\b|Acme\.\{[^}]*\bBilling\b|as: Billing\b' lib test --exclude-dir=hidden | grep -v '"Acme\.Billing"') &&
	fail "Acme.Billing still named: $left"
for pat in 'BillingAddress' 'Reports\.Billing' '"Acme\.Billing"' '\bBilling\.(summary|title)\('; do
	before=$(git grep -hcE "$pat" eval-base -- lib test | awk '{s+=$1} END {print s+0}')
	after=$(grep -rhcE "$pat" lib test --exclude-dir=hidden | awk '{s+=$1} END {print s+0}')
	[ "$before" = "$after" ] || fail "$pat: on $before lines before, $after now"
done
compiles
tests_pass
formatted_changes
