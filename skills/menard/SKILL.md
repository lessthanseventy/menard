---
name: menard
description: menard's AST-aware Elixir tools — which fits which change, and the traps no error message explains. Use for a rename across files, finding who calls a function, reading one function of a big module, and whenever an Edit on a .ex/.exs file is blocked (pi's guard).
---

# Editing Elixir with menard

In Claude Code, `Edit` works on Elixir, and menard's hook formats every file written and reports
what changed. These tools are for what an edit by hand does badly: a rename across files
(`rename`), who calls what (`find`), one function of a big module (`clause get`), a function
moved with its docs (`clause move`). Each parses the file, changes the tree, formats with the
project's formatter and parse-checks what it writes. Under pi's guard an `Edit` or `Write` on a
module is **blocked**, and these tools are how a module is edited at all.

Plain files, edited as usual: new files, `_build/`, `deps/`, `config/*.exs`, `.formatter.exs`,
`mix.lock`, and an `Edit` that only changes text inside a string (a heredoc, a `~H` template).

## Calling a tool

- **Claude Code**: MCP tools `mcp__plugin_menard_menard__<tool>`,
  verb as an argument.
- **pi**: `mcp({ tool: "menard__<tool>", args: {…} })`, the same arguments.
- **CLI**, where there is no MCP: `menard <tool> <verb> FILE …`, the same fields in order; a
  wrong call prints the usage. CODE full of quotes goes in a file, passed with `--stdin`. Run it
  by its path (`<the plugin's directory>/bin/menard`, as menard's own messages name it): a bare
  `menard` is whichever one the PATH holds first, which in Claude Code is not the plugin's.

`file` is relative to the project.

## Which tool

A big file: `outline {file}` instead of reading it — every module, and every clause's
`name_arity`, `head`, lines and doc, in far fewer tokens — then `clause {verb: "get", file,
name_arity}` for the one function you need. A file you have already Read needs no outline: its
heads are in what you read. A test file's outline lists its tests and describes with their lines, and `where
FILE:LINE` names the test a line (a failure's, a grep hit's) sits in. Then match the SHAPE of the change, not its size:

| changing | call |
|---|---|
| text, in several places or several files | `edit {edits: [{file, old, new}, …], then?: "test"}`: ONE call, where you would write a script |
| what a function does | `clause {verb: "replace", file, name_arity, head, code: BODY}` |
| its head, args or guard | `clause {verb: "rewrite", …, code: "def …"}` |
| one expression inside it | `stmt {verb: "replace", file, name_arity, head, match, code}` |
| a new function | `clause {verb: "insert_at", file, module, code}`; a new clause of one: `insert_after` its sibling |
| a clause's existence | `clause {verb: "delete" \| "insert_before", …}` |
| a whole function | `clause {verb: "delete", file, name_arity}`, no `head`: every clause; the reply's `left` is each call still to fix |
| public or private | `clause {verb: "visibility", file, name_arity, visibility}`: every clause at once |
| which file a function lives in | `clause {verb: "move", file, name_arity: ["a/1", "b/2", …], to, as?, moduledoc?, delegate: true}` |
| one module into several | `clause {verb: "split", file, plan: [{to, functions: ["a/1", …], as?, moduledoc?}, …]}`: the WHOLE split in one call |
| a function's `@spec` | `clause {verb: "spec", file, name_arity, code: SIGNATURE}`; no `code` removes it |
| a module attribute | `attr {verb: "get" \| "set" \| "delete", file, name, value}` |
| a test, describe, schema | `block {verb: "add" \| "replace" \| "delete" \| "relabel", file, name: "test", label, code, in?, args?, tag?}`; `replace` with a whole test under `@tag` lines sets its tags |
| tests into another test file | `block {verb: "move", file, label: ["a", …], to, as?}`: their @tags, the helpers only they call, the attributes and aliases they use go too; a new file gets the `use` and `setup`. A helper a staying test calls is refused: put it in test/support |
| an alias/import/use/require, a `doctest` | `directive {verb: "add" \| "replace" \| "remove", file, kind, target}` |
| one whole module of several | `module {verb: "replace", file, module, code}` |
| a `@doc` or a `#` comment | a plain Edit: a string and a comment are prose, and the guard passes an edit that changes only those |
| a name, everywhere | `rename {old, new, files: ["lib/**/*.ex", "test/**/*.exs"]}` |
| who calls what | `find {kind: "calls" \| "defs" \| "aliases", target, files}`: strings and comments never match; `calls` of `Mod.fun` adds the language server's `reference`s (below) |
| what a function uses, who calls its helpers | `deps {verb: "refs", file, name_arity}` |
| a project dependency | `deps {verb: "add", spec}` or `{verb: "upgrade", apps?, to?}`: fetches, compiles, answers with the lock diff |
| a whole new file | `write {file, code}` |

**`head` is an address: the clause's CURRENT head, copied from `outline`** (`head:
"%__MODULE__{items: items}"`), not what it will become. What the clause BECOMES goes in `code`:

- `replace`: `code` is the new body alone. The whole clause of the function named is taken as the
  rewrite it means; `block replace` takes a whole `test "…" do … end` the same way.
- `rewrite`: `code` is the whole new clause, new head included. Changing `total(cart)` into
  `total(cart, rate)` is `{verb: "rewrite", name_arity: "total/1", head: "cart", code: "def
  total(cart, rate) do … end"}`: the arity is the old one.

A function name repeated across modules is `Mod.Name.fun/2`.

## The language server

Claude Code also has the Elixir language server (expert, the plugin's `lspServers`), through its
`LSP` tool: definition, hover and references at a position. menard's MCP server keeps its own,
and `find calls Mod.fun` merges its answer in: a call through an `import`, a `defdelegate`, a `use`
or an `apply` comes back as `kind: "reference"`, which the AST alone cannot see. The reply's `lsp`
says what answered: the server's name, or which calls the AST's hits leave out while it is still
indexing or where there
is none (the CLI keeps none).

- **An empty LSP answer in a server's first half-minute is not "no callers".** Until it has
  indexed, a server answers nothing, or a short list. Ask `find` before deleting a function
  the LSP tool says nothing calls.
- `MENARD_LSP` picks the server, for both (`expert`, `elixir-ls`): `bin/lsp` is the one place
  that starts it.

## Traps

- **Several replacements are one `edit`, not a script.** Each `old` is found exactly once, as the
  edits before it left the file, or the whole call is refused and says which text was not there
  (a script's `replace` that finds nothing says nothing, and the edit is believed made). Nothing
  is written unless all of it is; `all: true` takes every occurrence; an empty `old` makes a new
  file. Through the shell it reads search/replace blocks: `menard edit --then test - <<'EOF'`,
  then for each: the file, `<<<<<<< SEARCH`, the text, `=======`, the new text, `>>>>>>> REPLACE`.
- **`test` and `describe` are macros, not functions**: `block` reaches them by `label`.
- **A zero-arity clause, or a function's only clause, takes `head: ""`.** Among several it is
  refused with their heads: copy one.
- **A head answers without its defaults.** `source, opts` finds `def f(source, opts \\ [])`.
- **An ambiguous head is refused with the candidates**; `nth` picks one.
- **`delete` takes the clause's `@doc`/`@spec` with it**; `insert_before` goes above them.
- **A split is ONE `clause split`**, not a script copying line ranges and not a move per
  function: `plan` names every new module's file and the functions that go there. Each one's
  private helpers, the attributes and alias/import/require lines it uses come along, a call back to
  the source is qualified, and a `defdelegate` is left for each public function, so the old module's
  API and callers keep working (`delegate: false` leaves none). A private helper a staying function
  also calls stays, made public (`published`), and the moved code calls it there. All of it is
  written or none: a refusal names the entry it stopped at. `clause move` is the same for one
  destination; without `delegate`, `left` is each call to fix.
- `stmt` reaches a line in a `do` block, a step in a `with`, a `case` arm, by what is WRITTEN: the
  whole statement or its unique start (`total =`); a line of a test with the test's label as `head`,
  and a statement of the module itself (`defstruct`, `@type t ::`) with no clause named. A miss
  lists what is there. A start matches the WHOLE statement: `case x do` is the whole case, so its
  `code` is the whole case too. `stmt replace` also
  reaches into a `~H` template: an expression in its `{…}`, or any text of it found once; the other
  verbs, and a heredoc, leave that text to `Edit`.
- `attr` refuses `@doc`/`@impl`/`@spec`, which repeat per clause: the clause verbs carry those.

## The reply

Its stages say what touched your code after you: `formatter` is `mix format`, `plugins` is the
project's plugins (Styler: sorted aliases, a collapsed pipe). Read them before looking for an edit
that moved. `unformatted` means written but not formatted, and says why.

Pass the reply's `version` back on your next edit to that file. If another session changed it
since, the edit is refused with the diff: re-read and redo it. `clause move` answers `{did,
created, moved, carried, attributes, directives, unresolved, qualified, delegated, published, left, to, from}`:
`to` and `from` are each file's own reply, its `version` and stages; `created` is the new module's
name when `to` did not exist; `carried` the helpers that came along; `published` the ones that stayed, made public; `unresolved` each call a `use`
or an import without `only:` may answer, which is not copied: add the one it names. `rename` answers `{did, changed,
unchanged, skipped}`: `changed` is each file's own reply, `skipped` each file it could not parse
or write, with why. Both doors give one reply: the CLI prints the MCP tool's map as one JSON
line, and a refusal is the same sentence at either.

## Done

While you work, `run {verb: "test", args: [FILES]}` with the test files of what you changed; `run
{verb: "check"}` once, when the change is done. `check` is format, warnings-as-errors and the tests in one JSON line: green, `ok`
and the counts; red, the failures. Every `run` verb answers `failures` in one shape: `kind` (`test`, `error`, `warning`, `format`, `credo`, and `step`: a precommit step nothing else read, named in `step`), `message`
(why) and `at` (`file:line`); a test failure adds its `source` and the assertion's `left`/`right`. `run {verb: "test", args: [FILE, "--repeat-until-failure", "50"]}` hunts a flake
and answers with the failing run's `seed`. One test or one describe, when you are editing the file
its line would drift in: go by name, `args: [FILE, "--only", "test:test NAME"]` (inside a describe,
NAME is the describe's name, a space, then the test's) or `args: [FILE, "--only", "describe:NAME"]`;
a name that matches nothing answers `ok: false` with no test run. A parse-checked write is a floor, not a proof: finish on
a green check.
