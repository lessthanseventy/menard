# step 02: server compiles clean; the hidden digest test and the MCP tests pass; get_digest is a tool
set -uo pipefail
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
grep -q 'name: "get_digest"' lib/server/mcp/endpoint.ex || { echo "FAIL: no get_digest tool in the MCP endpoint"; exit 1; }
out=$(mix test test/hidden/digest_test.exs test/server/mcp 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
