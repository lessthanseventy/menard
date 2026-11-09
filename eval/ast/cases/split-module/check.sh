# Acme.Catalog split into its five concern modules (the hidden test: every function there with its
# @doc, and still callable on Acme.Catalog), catalog.ex a facade with no code of its own, each
# describe's tests in its concern's test file and none lost; compiles clean, the suite passes.
source "$EVAL_COMMON"
for c in products pricing inventory search reviews; do
	[ -f "lib/acme/catalog/$c.ex" ] || fail "lib/acme/catalog/$c.ex missing"
done
code=$(grep -nE '^\s*(def|defp|defmacro|defmacrop)\s' lib/acme/catalog.ex) && fail "catalog.ex keeps code of its own: $code"
left=$(grep -csE '^\s*test "' test/acme/catalog_test.exs)
[ "${left:-0}" -le 1 ] || fail "$left tests left in test/acme/catalog_test.exs"
for want in products=26 pricing=24 inventory=24 search=26 reviews=24; do
	c=${want%=*}
	n=$(grep -csE '^\s*test "' "test/acme/catalog/${c}_test.exs")
	[ "${n:-0}" -ge "${want#*=}" ] || fail "test/acme/catalog/${c}_test.exs has ${n:-0} tests, ${want#*=} belong there"
done
compiles
tests_pass
formatted_changes
