---
name: menard
description: How to edit Elixir (.ex/.exs) with menard's AST-aware verbs instead of Edit/Write or sed — which verb fits which change, and the traps no error message explains. Use before changing any Elixir module, test file or directive, and when an Edit on a .ex/.exs file is blocked.
---

# Editing Elixir with menard

An `Edit` or `Write` on an existing `.ex`/`.exs` holding a `defmodule` is **blocked**. Use the verbs
instead: they parse the file, change the tree, and parse-check what they write, where a text
substitution is a guess whose failures are silent.

Exempt: new files, `_build/`, `deps/`, `config/*.exs`, `.formatter.exs`, `mix.lock`. **`Bash` is not
watched, and that is not permission**: `sed -i` on a module is just as wrong, only unenforceable.

## Calling a verb

**Claude Code** — MCP tools `mcp__plugin_menard_menard__<noun>` (`clause`, `stmt`, `block`,
`attr`, `outline`, …), with the verb as an argument. Paths are relative to the project.

**pi** — the `menard` MCP server's tools: `mcp({ tool: "menard__<noun>", args: {…} })`. Paths
are relative to the project root.

**CLI** (either harness) — `menard VERB …`. Paths are relative to where you stand.
**CODE full of quotes or backslashes:** write it to a file and pass `--stdin`, so the verb's last
argument is read from stdin, which no shell quoting can mangle.

## Which verb

Read the file first: `outline FILE` names every module, clause and doc in it. Then match the
SHAPE of what you are changing, not the size of the change:

| you are changing | verb |
|---|---|
| what a function does | `clause replace FILE name/arity HEAD BODY` |
| its head, args or guard | `clause rewrite FILE name/arity HEAD 'def …'` |
| one expression inside it | `stmt replace FILE name/arity HEAD MATCH CODE` |
| a whole clause's existence | `clause insert-after` / `insert-before` / `delete` |
| a whole new function | `clause insert-at FILE Mod.Name CODE` |
| which FILE a function lives in | `clause move FILE name/arity --to DEST [--as Mod.Name]` |
| a module attribute (`@colors`, `@hints`) | `attr get\|set\|delete\|list FILE @name` |
| the comment above one | `attr comment FILE @name [TEXT]`; no TEXT removes it |
| the comment above a statement, inside a body | `stmt comment FILE name/arity HEAD MATCH [TEXT]` |
| the comment at the top of a module (a test file's header) | `module comment FILE (Mod\|-) [TEXT]` |
| an ExUnit `test`, a `describe`, a `schema` | `block get\|replace\|add\|delete\|relabel FILE test --label "…"` |
| an alias/import/require/use | `directive add\|replace\|remove\|list FILE KIND MOD [OPTS]` |
| a name, everywhere | `rename OLD NEW [--only functions\|variables] [--atoms] [--comments] FILES` |
| a whole new file | `write FILE CODE` (`-` or `--stdin` reads it from stdin) |
| one whole module, in a file of several | `module replace FILE Mod.Name CODE` |
| a project dependency | `deps add [--in DIR] '{:req, "~> 0.5"}'` (or a bare name) · `deps upgrade [APPS] [--to REQ]` |

`replace` takes the **body**; `rewrite` takes the **whole clause**. Passing a `def` to `replace` is
refused, because `def bg, do: def(bg, do: X)` is valid Elixir and only the compiler would object.

What the verbs guarantee, where it is not obvious from the name:

- `stmt` reaches a line in a `do` block, a step in a `with`, and a `case` **arm** alike: address
  the clause, then the statement by what is WRITTEN. `list` prints what is there, and so does a miss.
- `clause insert-at` places by the code: a `defp` lands with the private functions. A new *clause*
  of an existing function is `insert-after`, named against its sibling; a different function given
  to `insert-after` goes after the whole function, never between its clauses.
- `clause replace` keeps a clause's form (`do … end` or `do:`) and its `rescue`/`after`.
- `clause visibility` flips EVERY clause at once: a half-flipped function does not compile.
- `directive add` places in Elixir's conventional order (use → import → alias → require,
  alphabetised), so the next format pass does not move it. `directive replace` changes a
  directive's options in place.
- `block add FILE test CODE --label L [--args '%{conn: conn}'] [--in "describe label"]` writes a new
  test, with its context if it takes one.
- `attr` refuses a name that repeats per clause (`@doc`, `@impl`, `@spec`); the clause verbs
  already carry those.
- `find calls|defs|aliases` is grep that knows the code: strings and comments never match.
- `deps add` writes the dependency into the deps list, fetches and compiles, and answers with the
  lock diff and the compile; a fetch that fails puts mix.exs back. `deps upgrade` goes through the
  host's own `mix igniter.upgrade` when it has Igniter, so each package's upgraders run.
- `clause move` carries the function's `@doc`, `@spec` and the comment above it, and takes EVERY
  clause. It does NOT touch aliases or call sites: that is the judgement, and `deps FILE
  name/arity` (what a function references, who else calls its helpers) is how you make it.

## What no error can tell you

- **ExUnit `test` and `describe` are macros, not definitions.** The clause verbs cannot address
  them; `block` can, by macro name with `--label`.
- **A zero-arity clause has no head.** `bg`, `bg()`, `def bg` and `""` all address it.
- **A head answers without its defaults.** `source, opts` finds `def f(source, opts \\ [])`.
- **An ambiguous head is refused, not guessed at.** `--nth 1..N` says which. Acting on "the first"
  silently is how a delete eats the clause that was just written.
- **`delete` takes the clause's `@doc`/`@spec` with it**, and `insert-before` goes above them. A
  `@doc` attaches to whatever definition *follows* it.

## Before you are done

`run [--in DIR] check`: format, warnings-as-errors, tests, in one call. `run test` and
`run compile` answer the same way: one JSON line, `{"ok":…,"tests":…,"failures":[…]}`, each failure
carrying its source, instead of output to grep.

**Hunting a flake:** `run test FILE --repeat-until-failure 50` repeats until the first failure and
answers with that run alone: its failures, its `seed` (rerun with `--seed N` to reproduce), and
`runs`, how many passed before it. Any other `mix test` flag passes through the same way.

The verbs format after every edit with the project's own formatter, so what you read next is what
the formatter wrote. The reply says what each step did: `patch` is what you wrote, `formatter` what
`mix format` changed, and `plugins` what the project's plugins (Styler) rewrote after that:
sorted aliases, a collapsed pipe, an added `@moduledoc false`. Read `plugins` before you go
looking for your edit and find it moved.

**Pass the reply's `version` back** (or `outline`'s, for the first edit) on your next edit to that file (`--version SHA`, or MCP
`version`). If another session changed the file since, the edit is refused with the diff since
your version: re-read what changed and redo the edit. `--force` writes anyway. `rename` and
`clause move` touch several files and take no version. A parse-checked write catches **malformed** output, not **wrong** output: it
is a floor, not a proof. Run the check.
