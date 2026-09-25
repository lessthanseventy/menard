---
name: menard
description: Editing Elixir (.ex/.exs) with menard's MCP tools, the verbs that parse, change the tree and parse-check — which tool fits which change, and the traps no error explains. Use before changing an Elixir module or test, and when an Edit on one is blocked.
---

# Editing Elixir with menard

An `Edit` or `Write` on an existing module is blocked; `sed` or a script on one is the same guess,
unguarded. Edit with the MCP tools `mcp__plugin_menard_menard__<tool>`: each parses the file,
changes the tree, formats with the project's formatter and parse-checks what it writes. `file` is
relative to the project. New files, `config/*.exs`, `.formatter.exs` and `mix.lock` are plain files.

## Which tool

Start with `outline {file}`: every module, clause (`name/arity`, its line, its head) and doc, in
far fewer tokens than reading the file. `Read` only the lines you need after it. Then match the
SHAPE of the change:

| changing | call |
|---|---|
| what a function does | `clause {verb: "replace", file, name_arity, head, code: BODY}` |
| its head, args or guard | `clause {verb: "rewrite", …, code: "def …"}` |
| one expression inside it | `stmt {verb: "replace", file, name_arity, head, match, code}` |
| a new function | `clause {verb: "insert_after", file, name_arity: SIBLING, head, code: "def …"}` |
| which file a function lives in | `clause {verb: "move", file, name_arity, to, as}` |
| a module attribute | `attr {verb: "get"\|"set"\|"delete", file, name, value}` |
| a test or describe | `block {verb: "add"\|"replace"\|"delete", file, name: "test", label, code, in?, args?, tag?}` |
| an alias/import/use | `directive {verb: "add"\|"remove", file, kind, target}` |
| a name, everywhere | `rename {old, new, files: ["lib/**/*.ex", "test/**/*.exs"]}` |
| who calls what | `find {kind: "calls", target: "Mod.fun", files}`: strings and comments never match |
| a whole new file | `write {file, code}` |

`head` is the clause's arguments as written, without defaults: `source, opts` finds
`def f(source, opts \\ [])`; a zero-arity or only clause takes `""`. `replace` takes the BODY,
`rewrite` the whole clause. A function name repeated across modules is `Mod.Name.fun/2`.

## Traps

- `test` and `describe` are macros, not functions: `block` reaches them, `clause` does not.
- An ambiguous head is refused with the candidates; `nth` picks one.
- `delete` takes the clause's `@doc`/`@spec` with it; `insert_before` goes above them.
- `clause move` carries the function but not its call sites or aliases: fix those after, with
  `find calls`.
- The reply's stages say what changed your code after you: `formatter` is `mix format`, `plugins`
  is Styler. Read them before looking for an edit that moved.

## Done

`run {verb: "check"}` is format, warnings-as-errors and the tests in one JSON line, each failure
with its source. A parse-checked write is a floor, not a proof: finish on a green check.
