# Menard

> Pierre Menard, author of the Quixote: rewrite a text word for word and have it come out
> different.

AST-aware edits and structured runs for Elixir, for an agent or a person at a shell. Every verb
parses the file, changes the tree, parse-checks what it writes and formats it with the project's
own formatter, plugins included: only the bytes a verb names move, and a half-applied edit is
impossible. `run` answers a test suite, the gate, a compile or a lint as one JSON line, every
failure with its file and line.

Parsing is not preservation: an edit can parse and still lose code. The identity corpus holds that
line. Every clause, attribute, block and statement in this repo and in a fixture of odd syntax is
replaced with itself, and the file must come back unchanged (`test/menard/identity_test.exs`);
`mise run bench:identity` runs the same edits over 22 pinned hex packages.

menard runs as a project of its own, on its own deps and toolchain (`.tool-versions`, through mise
where it is installed), so it keeps working on a codebase that does not currently compile, which is
where you need it most.

## Install

**In Claude Code**, as a plugin: the formatting hooks, the tools, the skill and an Elixir language
server, all from this repo.

```
/plugin marketplace add lessthanseventy/menard
/plugin install menard@menard
```

Or clone it: `mise run install:claude` from the Elixir repo you work in installs the plugin for
that repo (`--user` for every project), `mise run install:pi` wires pi, `mise run install:path`
puts `menard` on your PATH. The first call fetches and compiles menard's deps.

**As a library**, for a tool of your own: `Menard.Rename`, `Menard.Clause`, `Menard.Outline` and
the rest as plain functions, plus `mix menard.edit`, `menard.find`, `menard.outline`, `menard.run`,
`menard.map`, `menard.where` and `menard.deps` inside your project.

```elixir
{:menard, "~> 0.8", only: :dev, runtime: false}
```

The MCP door (`mix menard.mcp`) also needs the optional `{:anubis_mcp, "~> 2.0"}`. As a dep the
tasks run inside your project, so a dep that does not resolve or a `mix.exs` that does not parse
stops them; the CLI runs on either.

## Verbs

```
edit       replace text, in several places and files, in one call, all written or none
rename     a name changed everywhere it is used; strings and comments left alone
find       who calls a function, where a name is defined: grep that knows the code
outline    a file's modules and functions, with their heads and lines, in place of reading it
clause     one function or clause: read, replaced, moved with its docs; a module split
stmt       one statement inside a function, by what is written
block      a test, a describe, a schema: a macro's do block, by its label
attr       a module attribute
directive  an alias, import, require or use, put where it belongs
module     one whole module of a file that holds several
write      a whole file, parse-checked and formatted
deps       what a function uses; a dependency added or upgraded
run        tests, the gate, compile, format, credo: one JSON line, every failure with its file and line
map        every module of the project, its file and public functions
where      the function a file:line is in
version    which menard, on which Elixir and OTP
```

`menard help` prints this with an example of each, `menard VERB --help` what the verb takes with
an example of every call. A path is relative to the directory you are in; CODE full of quotes goes
on stdin, `-` in its place.

What every verb shares:

- **One reply, read whole.** stdout is the answer, one JSON line; stderr is only a refusal or an
  error. A writing verb's reply is every change it made, the formatter's hunks included, so there
  is nothing to read back; a refusal says what to do instead.
- **Nothing half done.** `edit` writes all of its replacements or none, `clause split` every new
  module or none; a text found twice, or not at all, refuses the whole call and says which.
- **`--then`.** Every writing verb takes `--then test` (the tests of what it changed, or
  `test FILE…`), `--then check` or `--then compile`, and answers with the run's result in `run`.
- **Versions.** Every writing reply carries the file's `version`; passed back as `--version SHA`,
  an edit against a file that changed since is refused with the diff (`--force` writes anyway).
- **`--frozen`** runs the last build straight off `_build`, no compile step: for editing menard
  with menard, where a half-applied edit would otherwise lock the tool out of finishing its change.

While you work, `run test` with the files of what you changed: seconds, and their failures alone.
`run check` once, when the change is done: the project formatted first, then its `mix precommit`,
or format, warnings as errors and the tests when it has none. Every failure is `{kind, message, at}`
with `kind` one of `test`, `error`, `warning`, `format`, `credo`; a test failure adds its `name`,
`module`, `source` and, for an assertion, `code`, `left` and `right`. A failed test runs once more,
and one that passes is listed under `flaky`, not `failures`.

menard complements Igniter. Igniter runs the installers and upgraders a package ships for its
users; menard is the edit an agent makes by hand. They meet at `deps upgrade`, which goes through
the host's `mix igniter.upgrade` when its lock has Igniter, so each package's upgraders run.

## In Claude Code

The plugin (`.claude-plugin/plugin.json`, `hooks/hooks.json`, `skills/menard/SKILL.md`) is two MCP
servers from one binary, the hooks that call them, and a language server.

**The hook.** Every `.ex`/`.exs` an `Edit`, a `Write` or a shell command writes is formatted with
its own project's formatter, plugins included (Styler, the HEEx formatter). What the formatter
changed goes back to the agent as context, so its next edit is written against the file as it is
now; a file that does not parse is named with the compiler's why. For a shell command the hook
marks the time before and formats every Elixir file newer than the mark after, on
`PostToolUseFailure` too. Each hook is an `mcp_tool` call to the hooks server already running
(`Menard.Hook`), with each project's formatter kept warm between writes (`Menard.Format.Worker`),
so a write costs milliseconds and starts no process. `bin/menard` in a session hands its verb to
that server over localhost (`Menard.Door`) and boots no VM of its own.

**The tools** are the verbs above, for what an edit by hand does badly: a rename across files, who
calls what, one function read out of a big module, a function moved with its docs, a module split
in one call. Claude Code loads their schemas on demand, so a session starts small and pays for a
tool when it asks for it. `bin/lsp` runs Expert, the Elixir language server, which `find` asks for
the references the AST cannot see.

## In pi

`pi/extension.ts` is a pi extension menard ships from this repo: format-on-save after every write,
and a pre-edit guard that turns a raw edit of an Elixir module toward the verbs, failing open when
menard is not there. `mise run install:pi` wires it, the MCP server and the skill into
`~/.pi/agent/`.

## Working on menard

`AGENTS.md` is the law here, and menard is dogfooded: its own Elixir is edited with its verbs. The
gate is `bin/menard run check`: format, warnings as errors, the suite with the identity corpus, and
a check that no host VM a test started outlives it. Design direction is in `docs/scope.md` (what
earns a verb), `docs/live.md` (the reply every verb should give) and `docs/adapters.md` (one core,
a thin adapter per harness).
