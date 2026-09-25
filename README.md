# Menard

> Pierre Menard, author of the Quixote: rewrite a text word for word and have it come out
> different.

AST-aware editing for Elixir. Every verb parses the file, changes the tree, and parse-checks what
it writes — so a half-applied edit is impossible, and only the bytes a verb names move
(Sourceror patches, not a reformat of the whole file).

It runs as a project of its own, which means `menard` keeps working on a codebase that does not
currently compile — the case where you most need it.

## Install

Two things ship, and they install differently.

**The library** — `Menard.Rename`, `Menard.Outline`, `Menard.Clause` and the rest as plain
functions, for a tool of your own:

```elixir
{:menard, github: "lessthanseventy/menard", ref: "<a commit>"}
```

Pinned by ref. Menard is not on hex: its mix tasks would run inside the host project, which is the
one thing the tool avoids, and `anubis_mcp` would become every user's runtime dependency.

**The verbs** — the CLI, the MCP door and the Claude Code hooks — run from *this* project, with
its own deps, which is what lets them work on a codebase that does not compile:

```
/plugin marketplace add lessthanseventy/menard
/plugin install menard@menard
```

Or clone it and put `bin/menard` on your `PATH`. Either way the first invocation fetches and
compiles its deps for you.

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
module  comment FILE (Mod|-) [TEXT]              the # comment heading a module
module  replace FILE Mod.Name CODE              one whole module, in a file of several
directive add|replace|remove|list FILE KIND MOD [OPTS]
rename  OLD NEW [--only functions|variables] [--atoms] [--comments] FILES
write   FILE CODE
run     [--in DIR] check|test|format|compile     test takes mix test's flags; answers with seed and runs
mcp                                            the same verbs over MCP
version                                        which menard, on which Elixir and OTP
```

`--stdin` reads a verb's last argument from stdin, for CODE that shell quoting would mangle.
menard runs on its own toolchain (`.tool-versions`, through mise when it is installed), never
the caller's.

`--frozen` runs the last build straight off `_build` with no compile step: the escape hatch for
editing menard *with* menard, where a half-applied edit would otherwise lock the tool out of
finishing its own change.

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
