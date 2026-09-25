# What belongs in menard

Status: direction, agreed in outline 2026-09-25. Andrew: "a swiss army knife for elixir dev …
minimal in most things, maximal in mcp servers and tech."

## The rule for a verb

A verb earns its place by adding something over running `mix X` directly:

- **a structured answer** instead of output an agent greps (`run test`'s failures, with their source),
- **a guard** against a trap that fails silently (`clause move` carries the `@doc`; `visibility` flips
  every clause),
- **working while the host is broken** (menard's formatter, when deps don't resolve or `mix.exs`
  doesn't parse).

A thin wrapper over one mix task adds surface and nothing else. That's why `inspect` and
`diagnostics` were cut.

## Shape

- **One tool per noun, verbs inside** (`deps add|upgrade|doctor`, `clause replace|…`). Agents pick
  worse from fifty MCP tools than from twelve; grow actions, not tools.
- **One reply for every verb**: what changed, what ran, what it found (`docs/live.md`). That's what
  makes thirty verbs one tool instead of a bag of scripts.
- **Portable across Elixir repos.** A repo's own glue stays in its mise tasks; menard is what
  travels (the ficciones cutover drew that line).

## Candidates, each from a pain already hit

| verb | the pain |
|---|---|
| `deps add\|upgrade` | a dep edited into `mix.exs` by hand, then `deps.get`, then a compile read by eye. As one verb: AST-aware edit, fetch, lock diff, compile result |
| `deps doctor` | a `_build` from another toolchain (1.19 vs 1.20, OTP 27 vs 29), deps stale or unfetched: menard knows the host toolchain now, so it can say so and offer the clean rebuild |
| `check` on touched lines | credo and dialyzer as data, filtered to the lines an edit changed |
| `xref` | callers and the dependency graph as data (was `inspect callers`, cut for being a bare wrapper; comes back only with structure) |
