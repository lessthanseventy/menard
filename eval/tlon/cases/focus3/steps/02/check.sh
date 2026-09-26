# step 02: server compiles clean and formatted; the hidden digest tests (Server.Digest itself, and
# get_digest over the wire: listed by tools/list, a tools/call answering the digest as JSON with
# `days` defaulting to 7) and the MCP suite pass
set -uo pipefail
source "$EVAL_COMMON"
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test test/hidden/digest_test.exs test/hidden/digest_tool_test.exs test/server/mcp 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
