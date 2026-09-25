# Changelog

## Unreleased

**New**
- A project's formatter plugins (Styler) are their own stage in every reply: `formatter` is what
  Elixir's formatter changed, `plugins` what the plugins rewrote after it, and which ran. What is
  written is still the project's full formatter output.
- `--version SHA` (MCP `version`) on every single-file writing verb: an edit against a version
  the file no longer has is refused, with the diff since that version. `--force` writes anyway.
  `outline` reports the version too, for the first edit.

- `clause spec FILE name/arity [SPEC]` (MCP clause verb `spec`): a function's `@spec`, set,
  replaced or removed. No verb reached it: `attr` refuses it and the clause verbs carry it.
- `module comment --above` (MCP `above`): the comment over `defmodule`, where a license header or
  a file's reason goes, not the one at the top of its body.

- menard's own examples are doctests (`Menard.Diff.hunks/2`, `Menard.jsonable/1`), kept
  formatted by `doctest_formatter`, a dev dependency.

**Fixed**
- A new attribute lands above the first node that reads it: a `@moduledoc` interpolating it, or a
  `use Foo, from: @it`. It went above the first table, below both, where the read is nil.
- A host's formatter plugins run from the host's directory. Quokka reads `.credo.exs` from the
  cwd; from menard's it found none and rewrapped every edited file at 98 columns.
- A plugin's cached config (Quokka's and Styler's `:persistent_term`) is forgotten before each
  format, so the MCP server no longer formats every host with the first host's config.
- `run --in DIR` with a pinned Erlang or Elixir that is not installed runs the `mix` on PATH and
  says so. It went through `mise exec`, which built Erlang from source and failed.
- `clause comment` on a clause whose comment sits between its `@doc` and the `def` replaces that
  comment, instead of adding a second above the `@doc`.
- `run test` kept only the first line of an error: a MatchError lost the value it could not match.
- `run format` with no files formatted nothing and answered ok; it takes the project's formatter
  inputs now, as its own `mix format` does.
- `run check` in a project with no `precommit` alias runs format, warnings-as-errors and tests
  itself, and says so (`ran`).
- A `run` whose deps are behind mix.lock (after a pull) fetches them, runs again, and names what it
  fetched (`fetched`), instead of failing on "dependency not available".
- `stmt` reaches a `with`'s steps and every arm of its `else` (and a `try`'s `rescue`): only the
  first block's body was reachable, and no step ever was.
- `stmt` MATCH may be the statement's start (`elixir_files =`) when no statement matches whole;
  several that start so are refused, each named by its first line.
- `clause replace` and `block replace` with a body that opens with the comment the old one opened
  with write it once, and clear a copy already doubled; a body with no comment leaves it alone.
- A new attribute lands above a def's `@doc`, `@spec` and the comment over them, never between
  them and the def, where the `@doc` was left belonging to nothing (and `clause doc` could not
  remove it).
- A write the format could not finish says so in its reply (`unformatted`, and the reason on the
  `formatter` stage), not on stderr only, where neither the agent nor its check saw it.
- The MCP door cannot go silent: every tool answers within a deadline (90s for an edit, 10
  minutes for `run` and `deps`), and a raise inside one is an error reply, not a dead call.
- The MCP `write` tool answered with the old `{did, file}`, not the staged reply.
- The CLI's `attr` reply did not name the verb.
- `outline --json` crashed on every file (a tuple in its answer, fixed for MCP in 0.3.0).

## 0.4.0

On hex, and every writing verb says what it changed.

**Install**
- The first release on hex (0.1 to 0.3 installed from git): `{:menard, "~> 0.4", only: :dev, runtime: false}` gives the library and the
  `mix menard.*` tasks inside your project. `anubis_mcp` is optional, so a library host brings
  only Sourceror; `mix menard.mcp` asks for it when it is missing.
- The pi adapter ships from this repo (`pi/extension.ts`): the guard and format-on-save.
  `mise run install:pi` and `mise run install:claude` wire either harness.

**New**
- The staged reply (`docs/live.md`, phase 1): every writing verb answers with `did`, the file's
  `version`, and per-stage hunks, what the verb wrote (`patch`) and what the formatter changed
  after it (`formatter`), so the file needs no re-read.
- `deps add [--in DIR] SPEC|NAME` and `deps upgrade [APPS] [--to REQ]`: a dependency written into
  `mix.exs`, fetched and compiled, answered with the lock diff. `mix.exs` goes back as it was when
  the fetch fails. Upgrades run through Igniter when the host has it.
- `module replace FILE Mod.Name CODE`: one whole module, in a file of several.
- A clause head copied off the def line (`def go(x)`, `go(x)`) finds its clause.

**Fixed**
- `block replace` with a whole block as the body nested the block inside itself. It is refused.
- A first MCP start took 42s and missed Claude Code's startup wait; it takes 13s, and the plugin
  declares a 180s timeout for a slow fetch.
- A formatter plugin built by a newer OTP logged a load error on every format before being passed
  over.

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
