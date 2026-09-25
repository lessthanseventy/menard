---
name: menard
description: How to edit Elixir (.ex/.exs) with menard's AST-aware tools instead of Edit/Write or sed — which tool fits which change, and the traps no error message explains. Use before changing any Elixir module, test file or directive, and when an Edit on a .ex/.exs file is blocked.
---

# Editing Elixir with menard

An `Edit` or `Write` on an existing `.ex`/`.exs` holding a `defmodule` is **blocked**; `sed` or a
script on one is the same guess, unguarded. Edit with menard's tools: each parses the file, changes
the tree, formats with the project's formatter and parse-checks what it writes.

Plain files, edited as usual: new files, `_build/`, `deps/`, `config/*.exs`, `.formatter.exs`,
`mix.lock`, and an `Edit` that only changes text inside a string (a heredoc, a `~H` template).

## Calling a tool

- **Claude Code**: MCP tools `mcp__plugin_menard_menard__<tool>`, verb as an argument.
- **pi**: `mcp({ tool: "menard__<tool>", args: {…} })`, the same arguments.
- **CLI**, where there is no MCP: `menard <tool> <verb> FILE …`, the same fields in order; a
  wrong call prints the usage. CODE full of quotes goes in a file, passed with `--stdin`.

`file` is relative to the project.

## Which tool

Start with `outline {file}`: every module, and every clause's `name_arity`, `head`, lines and doc,
in far fewer tokens than reading the file. `Read` only the lines you need after it. Then match the
SHAPE of the change, not its size:

| changing | call |
|---|---|
| what a function does | `clause {verb: "replace", file, name_arity, head, code: BODY}` |
| its head, args or guard | `clause {verb: "rewrite", …, code: "def …"}` |
| one expression inside it | `stmt {verb: "replace", file, name_arity, head, match, code}` |
| a new function | `clause {verb: "insert_at", file, module, code}`; a new clause of one: `insert_after` its sibling |
| a clause's existence | `clause {verb: "delete" \| "insert_before", …}` |
| public or private | `clause {verb: "visibility", file, name_arity, visibility}`: every clause at once |
| which file a function lives in | `clause {verb: "move", file, name_arity, to, as?}` |
| a function's `@spec`, `@doc`, or the comment above it | `clause {verb: "spec" \| "doc" \| "comment", …, text}`; no `text` removes it |
| the comment above a statement | `stmt {verb: "comment", …, match, text}` |
| a module attribute, or its comment | `attr {verb: "get" \| "set" \| "delete" \| "comment", file, name, value \| text}` |
| a test, describe, schema | `block {verb: "add" \| "replace" \| "delete" \| "relabel", file, name: "test", label, code, in?, args?, tag?}` |
| an alias/import/use/require, a `doctest` | `directive {verb: "add" \| "replace" \| "remove", file, kind, target}` |
| a module's header comment, or one whole module | `module {verb: "comment" \| "replace", file, module, text \| code}` |
| a name, everywhere | `rename {old, new, files: ["lib/**/*.ex", "test/**/*.exs"]}` |
| who calls what | `find {kind: "calls" \| "defs" \| "aliases", target, files}`: strings and comments never match |
| what a function uses, who calls its helpers | `deps {verb: "refs", file, name_arity}` |
| a project dependency | `deps {verb: "add", spec}` or `{verb: "upgrade", apps?, to?}`: fetches, compiles, answers with the lock diff |
| a whole new file | `write {file, code}` |

**`head` is an address: the clause's CURRENT head, copied from `outline`** (`head:
"%__MODULE__{items: items}"`), not what it will become. What the clause BECOMES goes in `code`:

- `replace`: `code` is the new body alone.
- `rewrite`: `code` is the whole new clause, new head included. Changing `total(cart)` into
  `total(cart, rate)` is `{verb: "rewrite", name_arity: "total/1", head: "cart", code: "def
  total(cart, rate) do … end"}`: the arity is the old one.

A function name repeated across modules is `Mod.Name.fun/2`.

## Traps

- **`test` and `describe` are macros, not functions**: `block` reaches them by `label`.
- **A zero-arity clause, or a function's only clause, takes `head: ""`.** Among several it is
  refused with their heads: copy one.
- **A head answers without its defaults.** `source, opts` finds `def f(source, opts \\ [])`.
- **An ambiguous head is refused with the candidates**; `nth` picks one.
- **`delete` takes the clause's `@doc`/`@spec` with it**; `insert_before` goes above them.
- **`clause move` carries the function, not its call sites or aliases**: fix those after, with
  `find calls`.
- `stmt` reaches a line in a `do` block, a step in a `with`, a `case` arm, by what is WRITTEN: the
  whole statement or its unique start (`total =`). A miss lists what is there.
- `attr` refuses `@doc`/`@impl`/`@spec`, which repeat per clause: the clause verbs carry those.

## The reply

Its stages say what touched your code after you: `formatter` is `mix format`, `plugins` is the
project's plugins (Styler: sorted aliases, a collapsed pipe). Read them before looking for an edit
that moved. `unformatted` means written but not formatted, and says why.

Pass the reply's `version` back on your next edit to that file. If another session changed it
since, the edit is refused with the diff: re-read and redo it.

## Done

`run {verb: "check"}` is format, warnings-as-errors and the tests in one JSON line, each failure
with its source. `run {verb: "test", args: [FILE, "--repeat-until-failure", "50"]}` hunts a flake
and answers with the failing run's `seed`. A parse-checked write is a floor, not a proof: finish on
a green check.
