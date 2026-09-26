# Menard

> Pierre Menard, author of the Quixote: rewrite a text word for word and have it come out
> different.

AST-aware editing for Elixir. Every verb parses the file, changes the tree, and parse-checks what
it writes — so a half-applied edit is impossible, and only the bytes a verb names move
(Sourceror patches, not a reformat of the whole file).

Parsing is not preservation, though: 0.2.0 fixed edits that parsed and still lost code (a
`rescue` dropped by `clause replace`). What guards that is the identity corpus: every `do … end`
clause, attribute, block and statement in this repo and a fixture of odd syntax is replaced with
itself, and the file must come back unchanged: byte for byte, or at least formatting the same
(`test/menard/identity_test.exs`). `mise run bench:identity` runs the same edits over 22 pinned
hex packages and counts each outcome.

It runs as a project of its own, which means `menard` keeps working on a codebase that does not
currently compile — the case where you most need it.

## Install

Two things ship, and they install differently.

**The library** — `Menard.Rename`, `Menard.Outline`, `Menard.Clause` and the rest as plain
functions, for a tool of your own, plus every verb as `mix menard.*` inside your project:

```elixir
{:menard, "~> 0.4", only: :dev, runtime: false}
```

`only: :dev, runtime: false` is for the tasks; a tool that calls the library at runtime drops both.
The MCP door (`mix menard.mcp`) also needs the optional `{:anubis_mcp, "~> 2.0"}`; without it,
menard brings only Sourceror.

As a dep, the tasks run inside your project, so they survive less of a broken build:

| your project | `mix menard.*` (hex) | the verbs below |
|---|---|---|
| its code does not compile or parse | works | works |
| a dep does not resolve | fails | works |
| its `mix.exs` does not parse | fails | works |

**The verbs** — the CLI, the MCP door and the harness adapters — run from *this* project, with
its own deps, which is what lets them work on a codebase that does not compile:

```
/plugin marketplace add lessthanseventy/menard
/plugin install menard@menard
```

Or clone it and put `bin/menard` on your `PATH`. Either way the first invocation fetches and
compiles its deps for you.

### Wiring a harness

menard ships one adapter per harness, all from this repo — no host repo required. `mise run
install:pi` and `mise run install:claude` write the right config into `~/.pi/agent/` or register
the Claude Code plugin. The plugin installs per project: run `mise -C ~/path/to/menard run
install:claude` from the Elixir repo, and its tools load there and nowhere else (`--user` for
every project). See `docs/adapters.md`.

## Verbs

```
outline FILE                                   what is in the file
find PATTERN FILES                             where a thing is
deps FILE name/arity                           what a function calls
deps    add [--in DIR] SPEC|NAME · upgrade [APPS] [--to REQ]   a project dependency, fetched and compiled
attr    get|set|delete|list  FILE NAME [VALUE]
attr    comment FILE NAME [TEXT]                the # comment above a table
clause  replace|rewrite|delete|insert-after|insert-before  FILE name/arity HEAD [CODE] [--nth N]
clause  insert-at FILE (Mod|-) top|bottom CODE
clause  move FILE name/arity --to DEST [--as Mod.Name]   with its doc, spec and comment
clause  doc|comment FILE name/arity HEAD [TEXT]
clause  spec FILE name/arity [SPEC]                 the function's @spec
clause  visibility FILE name/arity public|private
stmt    insert-after|insert-before|replace|delete|comment|list  FILE name/arity HEAD MATCH [CODE]
block   get|replace|add|delete|relabel|list  FILE NAME [CODE] [--label L] [--args CONTEXT]
module  add|list FILE [CODE]
module  comment FILE (Mod|-) [TEXT] [--above]    the # comment heading a module, or above its defmodule
module  replace FILE Mod.Name CODE              one whole module, in a file of several
directive add|replace|remove|list FILE KIND MOD [OPTS]
rename  OLD NEW [--only functions|variables] [--atoms] [--comments] FILES
write   FILE CODE
run     [--in DIR] check|test|format|compile     one JSON line; test takes mix test's flags, answers with seed and runs
mcp                                            the same verbs over MCP
version                                        which menard, on which Elixir and OTP
```

menard complements Igniter, it does not compete with it. Igniter runs the installers and upgraders a
package ships for its users; menard is the edit an agent makes by hand. They meet at `deps
upgrade`, which goes through the host's `mix igniter.upgrade` when its lock has Igniter, so each
package's upgraders run.

`run` answers what you look for: green, `{"ok":true,"tests":621,"failed":0,"failures":[]}`; red,
the failures and the seed that reproduces them. It answers every verb's failures in one shape, `{kind, message, at}`: `kind` is `test`,
`error`, `warning` or `format`, `message` says why, `at` is `file:line`. A test failure adds its
`name`, `module`, `source` and, for an assertion, `code`, `left`, `right`. `check` (format,
warnings-as-errors, tests) reports all three kinds the same way, with `test`'s counts.

stdout is the answer and stderr is only a refusal or an error: menard compiling itself after an
update is silent unless that build fails.

`replace` takes a body, and `rewrite` a whole clause; handed the whole clause (or `block`'s whole
`test "…" do … end`) of the very thing it names, `replace` takes it as meant rather than refusing.

Every writing verb answers with the file's `version`; pass it back with `--version SHA` and an
edit against a file that has changed since is refused, with the diff (`--force` writes anyway).

`--stdin` reads a verb's last argument from stdin, for CODE that shell quoting would mangle.
menard runs on its own toolchain (`.tool-versions`, through mise when it is installed), never
the caller's.

`--frozen` runs the last build straight off `_build` with no compile step: the escape hatch for
editing menard *with* menard, where a half-applied edit would otherwise lock the tool out of
finishing its own change.

## pi adapter

`pi/extension.ts` is a pi extension menard ships from its own repo (`bin/menard` and `hooks/`
self-located from `import.meta.url`: pi loads an extension as a `data:` URL, where
`import.meta.dir` is not a directory):

- **`tool_call` — the guard.** A raw `edit`/`write` on an `.ex`/`.exs` holding a `defmodule` is
  blocked — use the verbs instead. `menard guard FILE --edit INPUT` decides, so an edit that only
  changes text inside a string passes. Fail open: a missing menard never blocks an edit.
- **`tool_result` — format-on-save.** `menard run format FILE` on what was just written, so the
  file on disk is always formatter-compliant. Best-effort and invisible.
- **`tool_result` — advice.** `hooks/shell-edits.sh` and `hooks/read-hint.sh`, the scripts Claude
  Code runs, fed its payload shape; what they say is appended to the tool's result.

`mise run install:pi` wires the extension, the MCP server, and the skill into `~/.pi/agent/`.
Idempotent — re-running updates paths without duplicating. No ficciones, no Nix required.

## Claude Code plugins

Two plugins ship from this repo's marketplace, and the first is enough on its own.

**`menard`** (this directory: `.claude-plugin/plugin.json`, `hooks/hooks.json`) is one hook,
`hooks/format-report.sh`. Every `.ex`/`.exs` an `Edit`/`Write` or a shell command writes is
formatted with its *own* project's formatter, plugins included (Styler, the HEEx formatter). What
the formatter changed goes back to the agent as context, so its next `Edit` is written against the
file as it is now; a file that does not parse is named, with the compiler's why. For a shell
command it marks the time before and formats every Elixir file newer than the mark after, on
`PostToolUseFailure` too, since Claude Code runs `PostToolUse` only when a tool succeeds.

**`manos`** (`manos/`) is menard's hands: the MCP tools and the skill that says which fits
(`manos/skills/menard/SKILL.md`). Install it beside `menard` for what an edit by hand does badly:
a rename across files, who calls what, one function read out of a big module, a function moved
with its docs. Its schemas cost ~3.7k tokens in every turn, so it earns its place on projects
where those edits are common.

Why this split: the eval (`eval/STATUS.md`, bench5) measured menard as it used to ship, tools
plus a guard blocking `Edit` on modules, against the formatting hook alone. The hook gave the
same clean output at the cost of no menard at all; the tools cost 46% more for sonnet and paid
only on renames and big-file reads. The guard is gone from Claude Code: its blocks were a turn
each and bought nothing measurable over the hook. `hooks/menard-only.sh`, `shell-edits.sh`,
`read-hint.sh` and `prefer-menard-run.sh` stay for the pi adapter.
