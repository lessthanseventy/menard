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
the Claude Code plugin. See `docs/adapters.md`.

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
clause  visibility FILE name/arity public|private
stmt    insert-after|insert-before|replace|delete|comment|list  FILE name/arity HEAD MATCH [CODE]
block   get|replace|add|delete|relabel|list  FILE NAME [CODE] [--label L] [--args CONTEXT]
module  add|list FILE [CODE]
module  comment FILE (Mod|-) [TEXT] [--above]    the # comment heading a module, or above its defmodule
module  replace FILE Mod.Name CODE              one whole module, in a file of several
directive add|replace|remove|list FILE KIND MOD [OPTS]
rename  OLD NEW [--only functions|variables] [--atoms] [--comments] FILES
write   FILE CODE
run     [--in DIR] check|test|format|compile     test takes mix test's flags; answers with seed and runs
mcp                                            the same verbs over MCP
version                                        which menard, on which Elixir and OTP
```

menard complements Igniter, it does not compete with it. Igniter runs the installers and upgraders a
package ships for its users; menard is the edit an agent makes by hand. They meet at `deps
upgrade`, which goes through the host's `mix igniter.upgrade` when its lock has Igniter, so each
package's upgraders run.

Every writing verb answers with the file's `version`; pass it back with `--version SHA` and an
edit against a file that has changed since is refused, with the diff (`--force` writes anyway).

`--stdin` reads a verb's last argument from stdin, for CODE that shell quoting would mangle.
menard runs on its own toolchain (`.tool-versions`, through mise when it is installed), never
the caller's.

`--frozen` runs the last build straight off `_build` with no compile step: the escape hatch for
editing menard *with* menard, where a half-applied edit would otherwise lock the tool out of
finishing its own change.

## pi adapter

`pi/extension.ts` is a pi extension menard ships from its own repo. Two hooks, one tool
(`bin/menard`, self-located relative to the extension):

- **`tool_call` — the guard.** A raw `edit`/`write` on an `.ex`/`.exs` holding a `defmodule` is
  blocked — use the verbs instead. `menard guard FILE` decides; the extension only reads
  `input.path` and calls the verb. Fail open: a missing menard never blocks an edit.
- **`tool_result` — format-on-save.** `menard run format FILE` on what was just written, so the
  file on disk is always formatter-compliant. Best-effort and invisible.

`mise run install:pi` wires the extension, the MCP server, and the skill into `~/.pi/agent/`.
Idempotent — re-running updates paths without duplicating. No ficciones, no Nix required.

## Claude Code plugin

`.claude-plugin/plugin.json` and `hooks/hooks.json` make this directory a plugin. Two hooks:

- **`menard-only.sh`** (`PreToolUse`) blocks `Edit`/`Write` on any `.ex`/`.exs` holding a
  `defmodule`. It passes new files, `_build/`, `deps/`, `config/*.exs` and `.formatter.exs` —
  menard has no verbs for a bare keyword list, so those are edited directly. It does not watch
  `Bash`: a shell command has no structured target, and matching the command text blocks anything
  that merely quotes the pattern. Precision over coverage — a guard that fires on innocent
  commands gets switched off.
- **`format-elixir.sh`** (`PostToolUse`) formats whatever was written with the file's *own*
  project formatter, plugins included, so the formatter's output is what the next read shows.
- **`prefer-menard-run.sh`** (`PostToolUse`) points a bare `mix test`/`compile`/`format` at
  `menard run`, which answers in one structured line. Advisory — the command has already run, and
  that is what lets the match stay loose.

The guard exists because the rule "use menard for Elixir" was written down and then broken inside
the hour. A rule an agent has to remember is a rule it breaks.
