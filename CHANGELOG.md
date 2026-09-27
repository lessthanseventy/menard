# Changelog

## Unreleased

From an eval of agents editing a Phoenix fixture with and without menard (`eval/`): what the
agents tripped on, fixed, and what they reached for first, made to work.

**Changed**
- Every `run` verb answers `failures` in one shape: `{kind, message, at}`, `kind` one of `test`,
  `error`, `warning`, `format`. A test failure keeps `name`, `module`, `source`, `code`, `left`,
  `right`; its `error` is now its `message`, and an assertion's message is ExUnit's reason
  ("Assertion with == failed"), which it had none of. `run compile`'s `diagnostics` and `run
  format`'s `errors` are `failures`; `run check` reports all of them, where it had only a tail.
  `deps add`'s `compile` carries `failures` too.
- `run` answers what a reader looks for: green, `ok` and the counts; red, the failures and the
  seed. `exit`, `fetched`, a single run's `runs` and a tail that repeats the counts are gone from
  the printed reply (`Menard.Run.result/3` still returns them). `check` reports `tests` and
  `failed` like `test`, and its tail is ExUnit's summary, not the last lines of the log.
- menard compiling itself is silent unless the build fails: stderr carries only a verb's refusal
  or a real error, so it never has to be thrown away to read stdout.
- The skill leads with the MCP calls and their fields; the CLI is the fallback where there is no
  MCP. A CLI-first skill sent agents to menard through their shell.
- The Claude Code plugin loads its MCP tools up front (`alwaysLoad`): no ToolSearch round trip
  before the first edit, for ~3.7k tokens of schemas in every turn.
- `clause`'s tool description says what a head is: the clause's current one, as `outline` prints it.
- `clause move` answers `{did, created, to, from}` at both doors, `to` and `from` each file's write
  reply (its version and stages). MCP answered `{did, file, created}` and the CLI prose, with
  neither file's version.
- One verb layer under both doors (`Menard.Verbs.<Noun>.run/1`: params in, `{:ok, reply} |
  {:error, reason}` out). Every verb was written twice, once per door, and the two had drifted;
  now a mix task is argv → params → verb → one JSON line, and an MCP tool is its schema → verb →
  reply, so both give the same map and the same refusal. What that changed at a door:
  - The CLI's read verbs print the MCP reply as one JSON line where they printed prose: `attr
    get` (`{value}`), `attr list` (`{attributes}`), `block get` (`{body}`, or `{blocks}` among
    several), `block list`, `directive list`, `module list`, `stmt list` (`{statements, file}`),
    `deps FILE name/arity` (the report), and `find --json` (`{hits}`, not a bare list). `outline`,
    `map`, `where`, `find` and `version` keep their text forms, which the hooks read.
  - `rename` answers `{did, changed, unchanged, skipped}` at both doors, `changed` each file's
    write reply (its version and stages, which neither door gave), `skipped` each file with why
    (the CLI put those on stderr).
  - A field a verb cannot do without is refused by name at both doors (`clause move needs to`),
    where the CLI printed the usage; a file that does not parse is named at both (`lib/a.ex: not
    parseable — …`), where MCP left the file out; `attr` names a Phoenix `attr :x` declaration
    for what it is at both, where the CLI said only `no @x`.
  - `deps add|upgrade` that did not work (`ok: false`) is an answer at the MCP door, as `run`'s
    is, not a tool error whose text is the JSON.
  - The MCP `outline` tool takes `verb: "map"` (the project's modules, `all` for every function)
    and `verb: "where"` (`at: ["FILE:LINE", …]`, the function each sits in), the CLI's `map` and
    `where`, which MCP had no door to. Verbs on `outline`, not tools of their own: a tool per
    noun, and both are outlines.
- One error rule in the core: every `{:error, _}` an edit or read function returns carries a
  string (`Attr` answered `:missing`; `Rename` and `Outline` a raw parser term), and nothing in
  the core prints: `Menard.write/3` said an unformatted write on stderr itself, and the CLI door
  says it now, from the reply's `unformatted`.
- The host's formatter runs on the host's own toolchain, as one OS process per write
  (`Menard.Format`, `priv/format.exs`), never in menard's VM. It loaded the host's `_build` into
  menard's code path for good, checked beam compiler versions before loading, erased Styler's and
  Quokka's cached config, evaluated the host's `.formatter.exs` here, and changed the whole VM's
  cwd under a global lock; a plugin it could not load sent the file to the host's `mix format`,
  which evaluates `mix.exs` and the config first (live_beats: `config/dev.exs` wanted a GitHub
  secret, and the file went unformatted with three stack frames as its reason). Now `elixir` runs
  `Mix.Tasks.Format.formatter_for_file/2` in the host's project with its plugins from `_build`,
  and a plugin built by a newer OTP simply runs. The process never writes the real file, so one
  killed past its deadline cannot write it later. One process formats every file of one call:
  `run format` over a 69-file Phoenix project takes 1.5s where it took 2.9s; one write pays a VM
  start, ~0.4s, where the in-VM path took ~50ms after its first.
- A subdirectory's own `import_deps` resolve (live_beats' `priv/repo/migrations/.formatter.exs`
  imports `:ecto_sql`, which the root's does not): every file in the project failed on "Unknown
  dependency :ecto_sql", since only the root's imports were looked up.

**New**
- `run check` over a precommit alias whose failing step no parser reads (a `cmd` step) answers a
  failure of kind `step`: the step, as mix ran it, and the last lines it printed. It answered
  `failures: []` and a stack trace's tail.
- The guard passes an edit that only changes text inside a string or sigil (a heredoc, a `~H`
  template) or a `#` comment, where no verb reaches: `menard guard FILE --edit INPUT`, from both
  adapters.
- `block replace` and `block add` handed a whole block of the macro (and label) named take its
  body, label and args. Both were refused, and `block add` nested the block inside another.
- `block replace` handed a whole test under `@tag` lines sets those as its tags, in place of the
  ones above it: the one way to tag an existing test. The test came out nested in the old one.
- `run test` and `run check` answer `skipped` when tests were skipped (`@tag skip:`). `run test`
  counted them as nothing (5 tests, 3 skipped came back `tests: 2`) and `run check` never said.
- `mise run install:path` (and both install tasks) puts `menard` on PATH, `~/.local/bin`. Inside a
  menard checkout or worktree it runs that checkout's `bin/menard`; anywhere else, the installed one.

**Removed**
- The prose verbs: `clause doc`, `clause comment`, `stmt comment`, `attr comment` and `module
  comment` (with its `--above`). A `@doc` is a string and a comment is no node at all, so an `Edit`
  of either is what the guard now passes; each verb was one more schema to read for an edit `Edit`
  makes as well. `attr replace` (an alias of `set`) and `clause replace`'s fallback to `rewrite`
  when handed a whole clause are gone with them: one name per edit, and a whole clause handed to
  `replace` is refused toward `rewrite`, as it was in 0.5.0.
- The MCP server's instructions (in the client's system prompt) say modules are edited with its
  tools, from `outline`, finishing on `run check`: 4 of 6 smoke-run agents tried Edit first.
- `hooks/shell-edits.sh`: a module a shell command changed is named, with `run check` to confirm it.
  `hooks/read-hint.sh`: a whole-file read of a module over 300 lines is pointed at `outline`. Both
  advisory, in Claude Code and pi.
- `clause move` splits a module: `name_arity` takes several (a list, or `a/1,b/2`), one write per
  file, and `delegate: true` (`--delegate`) leaves a `defdelegate` for each public function moved,
  its defaults kept, so the old module's API and callers keep working. What the moved code needs
  comes with it: the private helpers only it calls, the attributes it reads (with their comment;
  gone from the source when nothing there reads them), and the alias/import/require lines it uses,
  only those (the source loses the ones it stops using, as they would warn). A call back to a
  public function that stays, and `__MODULE__`, name the source. A private helper a staying
  function also calls is refused, naming both, with the two ways out. `moduledoc` gives a created
  module its `@moduledoc`. The reply adds `moved`, `carried`, `attributes`, `directives`,
  `qualified`, `delegated` and `left` (without `delegate`, each call now pointing at nothing). In
  riverside1 every agent split ex_riverside's 860-line `events.ex` with a Python script copying
  line ranges and then hand-wrote ~50 delegates; the same split is now three moves and two
  `visibility` calls the first refusal asks for, and it passes step 03's check (grader, credo
  --strict, the API test, the suite). The guard's refusal and the skill say a split is one call
  per new module.
- `deps`: a head's defaults and guard count as what a function calls and reads (they travel with it).

**Fixed**
- `clause move` dedented the code it moved, and a heredoc `@doc`'s text with it: the patch left
  the text at column 1 and only the formatter put it back.
- Every CLI verb dropped a flag it could not read, and its value with it: `block add … --label
  "--x"` wrote a test with no name and answered as a success, and CODE like `-x + 1` lost its
  first token. Each verb now refuses it, saying `--flag=VALUE` or `-- CODE`, and what it takes.
- `bin/menard` fetched deps only when `deps/sourceror` was missing, so a checkout whose mix.lock
  gained a dep (a pull, a worktree moved to a newer commit) died on "dependency not available",
  told to retry `--frozen`. It fetches whenever mix.lock differs from the one last fetched for,
  quietly like its compile, and never under `--frozen`.
- A verb run without `--frozen` while menard does not compile left `--frozen` nothing to run: the
  failed compile had deleted the beams it was rebuilding ("module Menard.Source is not
  available"). The last good ones are put back.
- `block add` and `clause insert-at` wrote a blank line inside the new code as trailing spaces, and
  shifted the lines of a multi-line string inside it, changing its value.
- `clause delete` left a blank line under the module's `do`; deleting or moving a module's last
  function left one above its `end`. `clause move` to a new file in a directory that did not exist
  yet raised `File.Error`; the directory is made.
- `block replace` handed a whole test with args of its own (`%{tmp_dir: dir}`) kept the old ones,
  leaving its variables undefined.
- The format hook took every file git wrote after a `cd` (`cd DIR && git worktree add`) for an edit
  and formatted each; a command that started with `git` hid a real edit after it (`git checkout x
  && sed -i a.ex`). A file is skipped when its content is one its repo already holds, whatever the
  command.
- A verb whose build another process changed between `bin/menard`'s own compile and the verb's
  mix answered with mix's compile log ("Generated menard app" on stdout, ahead of the answer;
  "Waiting for lock on the build directory" on stderr). Every verb now runs off the last build
  the way `--frozen` did, with no mix project and no compile step, so its stdout is only its
  answer; `bin/menard` compiles first (quietly) when a source, or a dep's build, changed since.
- `run` past its deadline killed the Elixir task and left the host's `mix` running, and the
  plugin's client gave up at 180s while menard's own deadline was 600s: an agent's next `mix test`
  then raced the orphan in the same `_build` ("corrupt atom table"). The host's mix now runs under
  that deadline (coreutils `timeout`) and is killed at it, the reply saying what it was doing; the
  MCP door passes it one 20s short of the tool's, and the plugin's client waits 620s.
- The guard's MCP refusal sent agents to ToolSearch for tools `alwaysLoad` had already loaded.
- pi's guard never ran: pi loads an extension as a `data:` URL, where `import.meta.dir` is not a
  directory, so `bin/menard` was never found and the guard failed open.
- A parse error that carries a hint (a stray `end`) crashed the write with `String.Chars`, instead
  of refusing with the parser's message.
- `clause` named after a test (`total includes tax/0`) answered "have: none"; it now names the
  `block` call that reaches it.
- `clause rewrite` with a leading comment put it between the clause's `@impl` and its `def`.
- A `stmt` miss on text inside a template says to `Edit` it.
- An MCP `files` glob that matches nothing beside ones that do is dropped, not refused.
- The format hook blocked on a file whose formatter plugins will not load in menard's VM (a project
  never built in place) even when it was formatted already. `run format` checks such a file with
  the plugins left out, and passes it when it is formatted.
- A write in a host whose formatter plugins were built by a newer OTP (Tlön's Quokka, OTP 29) and
  whose mise config was not trusted answered a crash dump for its reason: OTP 27's `beam_lib`
  raised reading the plugin's atom chunk. Such a plugin is one that will not load, and the reply
  keeps mise's own "are not trusted" line, not its version and `--verbose` lines.
- `directive add` opening a new block (the first `alias` after the `import`s) wrote it with no
  blank line before it; Styler and Quokka added one, the bare formatter did not. It writes the
  blank line, and `directive remove` of a block's only line takes its blank line with it.
- `clause move` left a moved `@spec` naming a type the source defines (`t()`) as written, and the
  destination did not compile. A public type is named by its module (`Cart.t()`, aliased); a
  `@typep`, which no other module can name, is refused with what to do.

## 0.5.0

The identity corpus over 22 pinned hex packages (`mise run bench:identity`): every clause, attribute,
block and statement in their lib/ replaced with itself. 81,669 edits over 1,202 files: 96.5% come
back byte for byte, 1.6% differ only in what the formatter would rewrite, 1.9% are refused (an
ambiguous head, a module defined twice), and none changes the file. The first run changed 73 and
crashed 3; the fixes below are what it found.

**New**
- A project's formatter plugins (Styler) are their own stage in every reply: `formatter` is what
  Elixir's formatter changed, `plugins` what the plugins rewrote after it, and which ran. What is
  written is still the project's full formatter output.
- `--version SHA` (MCP `version`) on every single-file writing verb: an edit against a version
  the file no longer has is refused, with the diff since that version. `--force` writes anyway.
  `outline` reports the version too, for the first edit. `rename` takes `--version FILE=SHA` per
  file and `clause move` the source's, all checked before any file is written.
- `clause spec FILE name/arity [SPEC]` (MCP clause verb `spec`): a function's `@spec`, set,
  replaced or removed. No verb reached it: `attr` refuses it and the clause verbs carry it.
- `directive add|remove|replace|list` take `doctest`: a test module's `doctest Mod` line, placed
  after `use` and the aliases.
- `block add --tag T` (repeatable; MCP `tag`): the `@tag` lines above the test it adds.
- `module comment --above` (MCP `above`): the comment over `defmodule`, where a license header or
  a file's reason goes, not the one at the top of its body.
- An empty head addresses a function's only clause; among several it is still refused.
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
- `menard --frozen mcp` died at start (app.start outside a mix project); it serves now.
- Three of Sourceror's ranges are corrected before any verb patches with them, found by the hex
  corpus benchmark: a body starting `x not in y` began at `not`, and one starting
  `__MODULE__.A.f()` after `__MODULE__`, so a replace left those bytes behind (and `stmt` could
  not reach the statement); a literal before `end` ended on the space, and `fn -> nil end` became
  `nilend`.
- A module defined twice in a file (`if Code.ensure_loaded?(X) do defmodule M … else … end`) is
  refused by name, naming its lines. Every verb edited the first, whichever was meant.
- A multi-line value whose lines already sit at or past the target column keeps them there: a
  sigil's words or a heredoc's lines were pulled left when every line, the closing too, sat
  deeper than the base.
- A format out of time says which formatter it was waiting on (menard's VM, or the host's own
  `mix format` and why), and the budget is 60s: under load the host's `mix format` through mise
  took past 30s while a warm one took 3s.
- A line inside a multi-line string, sigil or heredoc is part of its value, and no verb moves it
  any more: re-placing a value or a statement shifted such lines, which changed the string.
- `rename` reaches a call inside `~H` (`:if={old(@x)}`, `<%= Mod.old(@y) %>`); it renamed around
  it and reported the file done, and the project stopped compiling.
- The MCP door cannot go silent: every tool answers within a deadline (90s for an edit, 10
  minutes for `run` and `deps`), and a raise inside one is an error reply, not a dead call.
- The MCP `write` tool answered with the old `{did, file}`, not the staged reply.
- The CLI's `attr` reply did not name the verb.
- `find` on a directory searches its Elixir files (it crashed); a path that matches nothing is
  refused by name (it printed nothing and exited 0); `find defs` no longer prints "def def".
- `attr delete` under a def's `@doc` takes the blank line it would leave between them.
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
