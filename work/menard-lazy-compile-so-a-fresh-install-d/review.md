VERDICT: REQUEST CHANGES

## Bug (confirmed, reproduced): duplicate `initialize` response, real instructions/capabilities dropped

`bin/menard`'s fast path answers the client's `initialize` request itself (a bare stub: empty
instructions, `capabilities: {"tools": {}}`), then later `exec`s the real Elixir server with that
same `initialize` line replayed on its stdin. The real server (`Menard.MCP`, `use Anubis.Server`)
has no awareness this request was already answered — `Anubis.Server.Session` unconditionally
replies to any `initialize` it receives (deps/anubis_mcp/lib/anubis/server/session.ex:705-708). So
the real server emits its **own, second** JSON-RPC response for the same request id.

Reproduced directly (fresh checkout, `bin/menard mcp`, same message sequence as the new test):

```
LINE: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"menard","version":"0.5.0"},"capabilities":{"tools":{}}}}
LINE: {"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{}},"instructions":"Several replacements of text, in one file or many, are ONE call to edit, …","protocolVersion":"2025-06-18","serverInfo":{"name":"menard","version":"0.5.0"}}}
LINE: {"id":2,"jsonrpc":"2.0","result":{"content":[…outline…]}}
```

Two consequences:
- JSON-RPC 2.0 forbids more than one response per request id; a strict client may treat the second
  as a protocol violation.
- The real server's `instructions` field — the one `lib/menard/mcp.ex` itself comments is load-bearing
  ("an agent reads this before its first call: in the eval, 4 of 6 learned it from the guard
  instead") — is sent but arrives *after* the client already completed its handshake on the fast
  stub's empty instructions, and is very likely ignored. This directly undermines the cited eval
  result and is the kind of regression this change should not introduce silently.

The new test (`bin_test.exs`, "mcp answers initialize fast…") does not catch this: it reads until
it sees `"id":1`, then reads until `"id":2`, and the duplicate `id:1` line lands unnoticed inside
`rest`; nothing asserts there is exactly one response per id, and nothing asserts the real
`instructions`/capabilities actually reach the client.

Fix needs to make the real server's `initialize` a no-op (or not replay it at all) once the fast
path has already answered it — e.g. have the real server skip emitting its own reply for that one
request when it was pre-answered, or have the fast path hand the real server the *real*
capabilities/instructions and only fill in the delay, not a second answer.

## Minor / lower confidence
- `version` in the fast reply is taken from the client's own requested `protocolVersion` and echoed
  straight back rather than reflecting what the server actually supports; harmless today since the
  echoed value matches reality, but it's not verifying menard supports whatever version a future
  client sends.
- The `menard_version` / `id` / `protocolVersion` extraction via `sed` happens to work for the
  current line shape (compact JSON, no spaces, `@version "x.y.z"` as a literal in mix.exs); fragile
  if either shape changes, but that's consistent with the rest of the file's style and not a
  regression.
- `hooks_test.exs`'s scratch path now embeds `System.pid()` twice (once inside `name`, once
  appended again) — redundant but harmless; read it as satisfying the scratch-dirs rule's textual
  check on the `tmp_dir` line, not a bug.

## Looks right
- `check_steps`'s switch to `tested/3` (mirrors the existing `run test` path at run.ex:486) and the
  `mise.toml` `check` task composing `test:elixir` + `test` (bun) both check out; the new
  `run_test.exs` case exercising the formatter-parsed failure path is a reasonable regression test
  for that half of the change.
- `mix_fetching`'s comment move back above itself is a pure no-op reshuffle, confirmed by diff.

Everything here was verified by reading the diff, running the merge-base diff, and reproducing the
duplicate-response behavior with a standalone probe against `bin/menard mcp` in this worktree —
not inferred from the PR description.
