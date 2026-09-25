# Changelog

## 0.3.0

One install, any directory, any harness: the plugin carries the MCP server and the reference.

**Install**
- The plugin declares the MCP server, with the project as its root. One install gives the verbs,
  the hooks and the MCP tools in every directory. Before, the server was registered per project.
- The verb reference ships as the plugin's skill (`skills/menard/SKILL.md`), its one copy.
- menard runs on its own toolchain (`.tool-versions`, through mise), never the caller's.
  `menard version` says which menard, on what.
- `menard guard FILE`: the enforcement any harness's pre-edit hook calls (`docs/adapters.md`).
  The Claude Code hook is now its adapter.

**Fixed**
- `menard mcp` never exited when its client went away, so every client that died left a server
  running.
- MCP `outline` crashed on every call (a tuple in its answer).
- A pre-compile swallowed the verb's stdin: `write FILE -` wrote an empty file, and before `mcp`
  the client's first message could be lost. An mtime check that never settled made that happen on
  every call.
- `write FILE -` with an empty stdin is refused instead of emptying the file.
- The MCP block tool treated an unknown verb as `replace` with empty code.

**New**
- `run test` passes every flag through to `mix test`. With `--repeat-until-failure N` it answers
  with the failing run, its `seed` and `runs`.
- `block delete`; `block add --args CONTEXT` for a test that takes its context.
- A clause head answers without its defaults.
- `--stdin`: a verb's last argument from stdin, for CODE no shell quoting carries intact.

## 0.2.0

Edits that no longer lose code, a formatter that works in a broken host, and the host's own
toolchain.

**Fixed: edits that parsed and silently lost code**
- `clause replace` dropped a clause's `rescue`/`catch`/`after`/`else`. It kept `do … end` vs `do:`
  either way, and handed a body like `if x, do: 1, else: 2` to the `def` in the keyword form.
  Now it keeps the form, and a `do:` body must read back as itself.
- `block replace`/`get` on a `do:` block deleted, or returned, the whole call line.
- A patch over a node that ends a line ate the newline (after a literal), or left quotes behind
  (an interpolated heredoc).
- Already-indented code was indented twice.
- `insert-after` with a different function landed between a function's clauses.

**Fixed: crashes and refusals**
- `alias __MODULE__.X` crashed `directive`, `find` and `deps`.
- `alias Foo.{Bar, Baz}` was invisible to `directive`, so `add` duplicated an alias already there.
- `rename` missed remote calls and captures (`B.old(1)`, `&B.old/1`).
- `Outer.foo/1` reached into a nested module's `foo/1`. Nested modules now have their full name.
- `stmt` could not reach a literal body (`{:ok, x}`, `:error`).
- A second `rescue` from `clause replace` parsed and did not compile; it is refused now.
- `attr get` on a missing attribute crashed instead of naming it.

**Formatting and the host**
- Every verb formats with the host's formatter in menard's own VM. Plugins load from the host's
  last build and `import_deps` from a cache, so it works while the host's deps don't resolve or
  its `mix.exs` doesn't parse. It never formats without one of the host's plugins; where menard
  can't load one, it falls back to the host's own `mix`.
- The host's `mix` runs under the host's toolchain (`mise exec`), not menard's.
- `run format` and the post-write hook use this formatter too.
- `run compile` no longer forces a full rebuild.
- A verb's stdout is only its answer: no compile log in front of it.

**New**
- `stmt comment` and `module comment`: the comments no verb reached.
- `directive replace`: a directive's options changed in one step.
- `rename --only functions|variables`.
- The MCP door gains `clause move`, `attr comment` and `block relabel`.
- `docs/live.md` and `docs/scope.md`: where menard is going.

**Removed**
- `diagnostics` (`run compile` answers the same) and `inspect` (thin wrappers over `mix xref
  callers`, `hex.outdated` and a Boundary-only export list).

**Plugin**
- Hooks run under `bash`: where `sh` is dash, the guard blocked every Edit and Write.
- The caller's directory rides `MENARD_CWD`, not mise's variable.

## 0.1.0

First release.

- Verbs that parse the file, change the tree and parse-check what they write, as Sourceror
  patches — only the bytes a verb names move: `outline`, `find`, `deps`, `attr`, `clause`,
  `stmt`, `block`, `module`, `directive`, `rename`, `write`.
- `run`, `inspect` and `diagnostics`: a project's gate, its call graph and a forced compile's
  warnings, each as one structured line.
- `mix menard.mcp`, the same verbs over stdio MCP.
- The Claude Code plugin: a `PreToolUse` hook that blocks `Edit`/`Write` on a module, a
  formatter pass on what is written, and a nudge from a bare `mix test` to `menard run`.
