# Changelog

## 0.8.15

- `run` no longer waits on a process the command left behind: a test that orphaned a child holding
  mix's output pipe kept `run test` waiting until that child died (half an hour, once). The host
  command's output goes to a file, read when it exits.

## 0.8.14

- A warm formatter's log no longer outlives it: a menard that halted (an MCP server's exit, the end
  of a test run) left one in TMPDIR per warm project, hundreds a day. The host VM is given its log
  and removes it when its caller is gone.

## 0.8.13

- The session's opening text says `edit` is for any file, and which languages are parse-checked
  and linted: a Zig session read "Every Elixir file written…" as menard being Elixir-only and
  wrote around it. The note after a run of Edits says "of any language" too.
- biome formats a new file only where the repo has a `biome.json` or `biome.jsonc` between the
  file and its top: biome's defaults are no house style.

## 0.8.12

- A Zig row in `Menard.Lang`: `zig fmt` refuses what does not parse and formats a file in its
  style at HEAD; `zig ast-check` lints the lines changed. An unused local is a lint, not a
  refusal: a change half made would be locked out.
- A TypeScript and JavaScript row: biome checks, formats and lints `.ts`, `.tsx`, `.js`, `.jsx`
  and their `m`/`c` kin. A write is refused only on biome's own parse diagnostic: biome exits 1 on
  every file under a `biome.json` it cannot read.
- A file that is not Elixir is no longer reported as Elixir-formatted beside a host's formatter
  plugins: the plugin split ran `Code.format_string!` on any file, and a `.ts` edit in a Styler
  repo was said to become `const(a = 1)`.

## 0.8.11

- A shell command's hook leaves Zig's `zig-pkg` and `.zig-cache` alone, as it does `deps` and
  `_build`: Zig 0.17 fetches dependencies into the project's own tree, and a build's first fetch
  had their vendored shell scripts reformatted as the agent's writes.

## 0.8.10

- The session's opening text says the check is its own call, read before a push: a session
  joined its gate to `git push` with `;`, and the push ran whatever the gate said.
- A session idle past 30 minutes still answers its hooks: anubis ended the stdio session, and
  every hook after waited out its timeout, about two minutes a Bash call. Every hook's timeout is
  15 s, and a server that stopped answering is told apart from one that is up (`alive`).
- A server whose MCP session ended, for any reason, starts it again itself, initialized without
  the client's handshake, and says so on stderr: anubis starts no second session and Claude Code
  initializes once, so every call after went unanswered.
- The write verbs and `run` reach any git checkout under the home, not only the session's
  directory; a sibling file's `then` runs in its own project.
- Claude Code's `Edit`, `MultiEdit` and `Write` on an `.ex` or `.exs` file are refused for `edit`,
  outside `deps`, `_build`, `.git` and `node_modules`; an `.ex` that is no Elixir (an EEx
  template) is left to them, as `edit` would not write it.
- A run whose `_build` lock cannot be taken says so; a run's mix is given neither the session's id
  nor `MENARD_ROOT`.
- A fixture repo under an ignored `tmp/` is left alone on macOS too.
- `menard --help` through `head` runs as written.
- Under auto mode, a command the hook would rewrite is refused with the command to run: auto mode
  gave no verdict on a call a hook had changed.
- A refused batch says its other edits are kept unwritten for the retry.
- A script refused in the shell is shown the shell's `edit` first, then the tool.

## 0.8.9

A review of the whole tool before it went to Hex; what it found, fixed.

Package and CLI:

- `menard --version` and `-v` are `menard version`.
- In a host, `mix menard.VERB --help` answers the verb's help, and the help names `mix menard.…`
  where there is no `bin/menard`. `mix test.no_leaks` is no longer in the package.
- A flag that names a field (`rename --old a --new b --files lib`) is read as that field; the
  verb's positional shape no longer waits for it too.
- The package runs on Elixir 1.18, checked there.

`edit`:

- A file of CRLF lines is found by text written with LF, and keeps its line ends.
- A file with no newline at its end, that is not code, keeps none.
- A symlink and its target named in one call are one file: both edits land.
- A file rewritten on nearly every line is diffed at once, not for 15 s an edit.
- `replacements` counts every place an `all` replaced; a refused batch removes the directories
  it made; the batch kept for `--retry` is in the user's cache, read as data.

`rename`:

- The new name is checked: `bad name`, a module's name for a function, or an arity on the old
  name (`A.go/3`) is refused before a file is read.
- A rename onto a function the module already has is refused: the two would be one.
- `Mod.fun` follows into `import Mod, only: [fun: 1]`; by name, into `defoverridable` and
  `@compile {:inline, …}`.
- A module defined inside its parent is renamed where it is defined; `Elixir.Old` follows.
- An alias is its own module's: `A` aliased differently in two modules of a file is two modules.

`find`, `outline`, `map`:

- `find calls` no longer lists a `@spec` or `@callback` as a call, and a hit's text is code, not
  the comment above it. `find defs` checks its target.
- `outline` names `defmodule __MODULE__.Child`, finds a module under an `if`, and shows a
  `~S"""` doc's first line. `map` skips only a top-level `deps/` and `_build/`.

`run`:

- An umbrella's test run answers every app's counts and failures, each at its path from the root.
- A red run no longer answers `tests: 0, failures: []` when the formatter's snapshot landed on
  the suite's end.
- A warning written over several lines is its whole message. A run stopped at its deadline says
  so. A run that finds another still going answers that, with `waited`, and leaves its lock.
- `run format` names a file that is not there and a `.formatter.exs` that raises; one that
  computes its inputs is evaluated in its own directory.
- A piped `mix test` keeps its environment (`env FOO=1 mix test | tail`).
- The warm formatter restarts when a dependency is built again. A failed `deps add` leaves no
  lock behind.
- A failure's message, `left` or `right` of more than 2,000 characters (the map a `KeyError`
  missed in) is its start, and says the log has the rest.
- `run check --committed` (and `test`, `compile`) runs the last commit in a worktree menard keeps,
  its build warm from the run before: the files can be edited while the gate runs. The reply
  names the commit, and how many changed paths it did not see.

`clause move`:

- A private function named in a move that what stays calls too is no longer refused: it goes,
  public where it lands, and the staying calls name it there.
- When the move leaves the two modules calling each other, the reply's `cycle` says what to move
  to end it.
- `clause move --help`, and `--help` after any noun's verb, is the help.

Hooks and the door:

- The door takes a token, kept in its file (0600): another local process cannot run verbs
  through it. It greets the launcher, bounds a request in time and size, and is found by the
  harness's pid when the session's id has changed (`/clear`).
- A rewritten command is allowed without a prompt only when it is menard's own `run`; anything
  else goes by the user's permission rules.
- What a subagent has read is its own. A session standing in `~` is not walked after every
  command. A payload whose input is no object is answered, not a crash. A session's start
  answers one JSON document.
- The launcher and hooks run under macOS's bash 3.2, BSD `stat` and no `timeout` (written from
  the manuals, run on no Mac).
- The LSP client sends percent-encoded URIs and UTF-16 columns.
- An MCP call of more than 30 s answers. The transport gave every request 30 s and, past it,
  wrote no response: a `run check`, or an `edit` whose `then` ran a slow test file, did its work
  and the call hung until the client gave up.
- A server whose install is replaced under it (a plugin reinstall, with sessions open) goes on:
  from the code it has loaded, all of it at start, while the new install is not there yet, and
  from the new install once it is, built and loaded as changed source is. It rebuilt itself from
  files half there, crashed, and went silent for good: every hook then waited out its timeout,
  130 s on each Bash call, until the session was restarted. (Stopping it was no cure: Claude
  Code does not start a stopped server again, and the session ran on with no hooks.)
- A session resumed has menard on its PATH once: each start added a line, an updated plugin's
  older versions staying among them.
- A piped test run rewritten to `mise exec -- menard run test` is approved as menard's own run
  is. `run credo` is as strict as the project gates. Through MCP a call's directory goes with it
  into the process that runs the verb. The session-start text says `mix test`'s flags pass
  through `run test`, `--slowest` and `--slowest-modules` answering as data.

And from before the review:

- `edit` with a `then` runs credo on the lines it changed and puts the findings in the reply's
  `credo`, beside the compile or test it ran. Under the hooks server credo's note came a call
  later, beside whatever the session did next, and a nesting finding was passed over until the
  gate. For that call the hook adds nothing, through MCP or the CLI; with no `then`, its note is
  as before.
- The session-start text and the script refusal teach the MCP `edit` tool first, its `edits` list
  shown, with the CLI heredoc as the shell's form. Agents used the CLI because nothing else was
  shown, and took it for the only way to edit several files at once.
- Through MCP a relative path is from where the session stands, as the shell's is. The server
  starts in the session's first directory and heard nothing of a `cd`: a session started in
  `~/projects` and working in `~/projects/thatch` had `lib/x.ex` looked for, or made, in
  `~/projects`. A PreToolUse hook on menard's tools leaves the call's `cwd` for the server, by the
  session's id.
- An edit through menard's MCP tools gets credo's notes on the lines it changed, as a Write and a
  shell command do. Its hook recorded what it wrote and said nothing.
- `edit` of a file that is not there names where it looked.
- `edit --then test` beside a file that is not Elixir (a `hooks.json`) no longer crashes: only
  Elixir files are read for the modules a test names.

## 0.8.8

- The MCP servers stop when Claude Code stops them. SIGINT opened the BEAM's BREAK menu on stdout,
  the protocol channel, and the default SIGTERM outlasted the harness's wait, so a server was
  SIGKILLed and its session told its hooks were down. SIGINT's menu is off and SIGTERM halts.
- The session-start text says how to run tests (`run test`) and finish a change (`run check`), and
  that every written Elixir file is formatted. It described only the piped-test rewrite, which read
  as leave to pipe. On a fresh install or an update, when menard is not built yet, the text comes
  from `hooks/upfront.txt` (a test keeps it equal) instead of nothing.
- The formatting hook leaves a test's fixture alone when a repo around it ignores it, up to the
  session's directory: a fixture is a repo of its own, and a suite run in an agent's worktree had
  its fixtures linted as the session's writes.
- `edit --then test` runs each changed file's mirror test, else the test files that name its
  modules, else nothing and says so. It fell back to `mix test --stale`, which in a fresh worktree
  ran the whole suite and otherwise every test touched since the last `--stale`: of 366 such runs
  in two weeks, 169 ran 30 tests or more.
- One `run test` at a time in a project, as `run check` already was: ExUnit gives a test the same
  `tmp/` directory in every run of a checkout and clears it as the test starts, so a second run
  deleted the first's fixtures mid-test. The next waits, and says how long.
- Each project keeps its own run-log directory. The name was the path cut to 60 characters, so
  projects under one long path shared it, and each rotation deleted the other's logs.
- The week-old sweep of menard's temp files runs once a day, not at every session start, which
  stat'ed every run log there was.
- `rename` of a module: nested names (`Acme.Billing.Error`) and a multi-alias's entry are renamed;
  an entry whose new name has another base leaves the braces for its own alias; and `alias Old`
  binds the bare last name per module, not per file. `alias X, as: Pay` no longer counts as
  binding `X`'s last name.
- A `require` only the moved code used leaves the source in `clause move`/`split`: it failed
  `--warnings-as-errors` under Elixir 1.20.
- A dev checkout's `bin/menard` uses only a door its own checkout's server opened, not the
  installed plugin's.
- `@spec` on every public function written by hand.
- The suite runs half the cores' worth of cases and starts every VM with four schedulers: at the
  default it pegged the machine and ran single tests past their timeout, for no shorter a run
  (290 s now, against 374 s).

- `rename OLD NEW` with a module name renames the module: its `defmodule`, its aliases and every
  call that spells it, strings and comments left alone. A dotted name was read as `Mod.fun`, and a
  module rename answered "unchanged" for every file.
- A module `clause move` or `clause split` creates keeps the prefix its source carries past its
  own path: `Excessibility.TelemetryCapture` split to `lib/telemetry_capture/writer.ex` is
  `Excessibility.TelemetryCapture.Writer`, not `TelemetryCapture.Writer`.
- A directive added under a heredoc `@moduledoc` takes its own line. Sourceror ends a heredoc a
  column past its line, and the patch there ate the newline, so an alias a move added ran into
  the line below and left the source unparseable.
- Every parse failure names its line with an excerpt, from `write`, `edit`, `clause` and
  `module` alike; three of them answered the raw error tuple. A split that stops names the move
  it stopped at and says nothing was written.
- An `edit` of a file that defines the same module twice (one `defmodule` per branch of an `if`)
  no longer crashes the layout pass with a MatchError after the batch's earlier files were
  written: such a module is left as written.
- A crash writing one file of an `edit` batch puts back the files written before it and is
  raised as it was; the layout crash above left them on disk, and so would any other.
- `clause move` and `split` compare alias names as strings: no atom is made from a name read
  out of a file.
- The formatting hook asks each file's own repository what git ignores, not the session's
  directory. A suite run while the session sat elsewhere formatted every fixture the suite wrote,
  a warm host VM per fixture.
- `mix test_no_leaks` gives a warm host VM twenty seconds to notice its owner gone, not six:
  beside another suite on the same box, VMs on their way out were counted as leaks and killed.
- Comments carry only the why: history, incident references and review citations are gone from
  lib, bin, hooks, priv and the tests. `and`/`or`/`not` on booleans throughout.
- The README describes the verbs, the plugin and the install paths as they are.

## 0.8.7

- The skill's opening says what the machine-wide rule says: every Elixir change goes through
  menard, `edit` for a text replacement and the AST tools for the rest; Claude Code's `Edit` is for
  what menard does not cover. It said `Edit` works on Elixir and menard was for the hard cases.

From the transcript review of 2026-11-08 (`docs/review/2026-11-08-transcripts.md`):

- `menard … 2>/dev/null || fallback` is not refused: only stderr went to /dev/null, the reply was
  kept. `&>/dev/null`, which throws the reply away, is refused, where it passed.
- A dependency's compiler warnings (styler's, doctest_formatter's under Elixir 1.20) are no longer
  the project's `failures` in a green `run test` or `run check` reply.
- An `edit` of a file that cannot be written (a sandbox's read-only scratch dir) answers one
  sentence, `cannot be written: permission denied`, not `File.write!`'s stack trace, and puts back
  the files it wrote before it.
- A subagent brief that itself says "use `menard find calls …`" is not refused as a call search.
- A script with no extension that a shell command wrote (`bin/tool` with a bash shebang) is
  checked by its shebang after the command, as a `.sh` was; its syntax error was never seen.
- The filter refusal says which it saw: the reply sent to /dev/null, or a filter on it.
- `bin/menard VERB` boots no VM of its own in a Claude Code session: the session's hooks server
  listens on a port of localhost's (`Menard.Door`, the port in `$TMPDIR/menard-door-SESSION`) and
  the launcher sends the verb there over bash's `/dev/tcp`, the formatters already warm. An
  `edit` from the CLI took 24 s at the median under the seats' load, where the same edit through
  the MCP door took 1 s. `run` keeps its own VM, as does every verb from inside menard's checkout;
  a door that does not answer costs one refused connection, and the verb runs as before.
- A session whose hooks server is not running (its connection timed out at startup, or it stopped)
  is told so once, at the next prompt after the first, with how to reconnect it; before, three
  sessions in a month ran with no hooks and no word of it.
- A verb whose stderr nobody can write (`2>&-`, a sandbox denying the temp dir) exits 1, where the
  VM died at boot with the crash as an Erlang term on stdout.
- The shell lint follows what a script sources beside it (`shellcheck -x`), so a hook's
  `source lib.sh` is no longer "SC1091: not following" and lib.sh's variables are assigned.
- `block move` to a new file carries the source's `@moduletag` lines and the one bare `import`
  the moved tests call through; a bitstring's `binary-size(2)` is no longer read as a call.
- CODE as `-` reads stdin for `block`, `clause` and `stmt`, as it did for `write` and `module`.
- A parse refusal shows the line it points at and the one before it.
- `clause move` takes `public: true` (each moved function public in its new module: private
  helpers into test/support in one call), and `left` is five call sites per file, then how many
  more, not sixty lines.
- `clause move`'s `left` scan parses only the files that name the function, as `find` does: a
  move with no `root:` parsed every file under the cwd for a name none had, 60 s under load.
- menard renders code with no `.formatter.exs` read of the cwd's: Sourceror read it on every call
  through the VM's file server, and under load that stalled three `clause move` tests to their
  60 s. The checkout copies the tests make go through `cp`, not that server.
- `clause get FILE:LINE` reads the function around that line, the shape a stack trace or a
  failing test hands over; a line no function spans says what ends before it and starts after.
  Before, a read by name needed an outline first, and the read was `sed -n` instead.
- A call no shape takes says what it was given, under the usage lines: the verb, how many
  arguments, and the last of them (the one too many, as a rule).
- `bin/release` refuses a main behind origin/main, not one ahead of it: ahead is where every
  release starts, since it pushes.
- A fresh install beside a built older version (the plugin cache's layout) starts from that
  version's deps and build, and fetches and compiles only what changed since: 5 s to the first
  answer, where compiling from nothing took 40 s, past the harness's 30 s to connect a server,
  and a version's first session ran with no hooks (0.8.7's did, until reconnected by hand).
  `bin/release` builds the installed plugin too, right after updating it.
- menard's own gate: 554 s to under 420 s at load 10, the identity corpus in eight modules and the
  long test files split into modules that run beside each other (with `clause move` and
  `block move`, which is what found the three fixes above).

## 0.8.6

- menard runs on Elixir 1.20.4 / OTP 29.0.6 (`.tool-versions`), from 1.19.4 / 27.3.4.2. A host's
  own formatter and tests still run on the host's toolchain.
- `mix menard.mcp` under `MENARD_LOG_LEVEL` logs to stderr again on OTP 29, which gives a handler
  named `:default` filters that drop every Elixir log.
- The gate's second compile under 1.20 is gone: 1.20 is the pin.
- A host that takes menard without the optional `anubis_mcp` builds it with no warnings: the
  `mix menard.mcp` task named two modules that only exist with it, a warning each.

## 0.8.5

- A host whose `mise.toml` / `.tool-versions` pins erlang or elixir that mise does not load
  (untrusted, ignored) is refused, not run on menard's own toolchain: that run rebuilt the host's
  `_build` on the wrong OTP (tlon's `server/` on 27 under a pin of 29). The reply names the config
  and `mise trust` for it; formatting there fails with the same reason.
- A verb whose stderr is a pipe with its reader gone (`menard … 2>&1 >out | true`) exits with the
  verb's own status, not 141 from the shell's SIGPIPE on passing that stderr on.
- The language server `bin/lsp` starts (Claude Code's `lspServers` start it, not `bin/menard`)
  dumps a crash to `$TMPDIR/menard-erl_crash.dump` too, not into the project.

## 0.8.4

- A VM menard starts that crashes no longer leaves `erl_crash.dump` in the caller's project: it goes
  to `$TMPDIR/menard-erl_crash.dump` (`ERL_CRASH_DUMP`, exported by `bin/menard`; one you set
  wins). The boot crash behind tlon's dump, a print to a `standard_error` that is gone, is not
  reproduced yet and is in TODO.md.

## 0.8.3

- A `menard …` command whose reply is piped into a filter that ends the line (`| head -c 3000`,
  `2>&1 | tail -c 1500`, `| jq .failures`) is run bare in its place, and the agent is told in one
  line that the filter was dropped. It was refused, a turn lost each time: ~200 of tlon's 271 tool
  denials in 14 days. A filter with a command after it, a heredoc, a loop or `>/dev/null` is still
  refused.

## 0.8.2

- `bin/menard` under a sandbox that denies the temp dir, as Claude Code's does on macOS, exited before
  the verb ran: `edit` wrote nothing. The verb now runs with its stderr uncaptured when no temp file
  can be made, and the self-rebuild's backup of the last good beams lives in `_build`.
- `mix precommit` hung on an install with no Hex, at "Shall I install Hex? [Yn]": the Elixir 1.20
  compile now fails at once, and its message names `mix local.hex --force`.
- The suite passes on macOS: a hooks test used GNU's spelling of `sed -i`.

## 0.8.1

- `edit` crashed with a `FunctionClauseError` in `Sourceror.get_line/2`, before writing anything, on
  valid Elixir that ends in a literal with a comment on a line after it (a `.formatter.exs` with a
  last comment). Every verb's parse now takes it: the comments stay in the file.
- `edit` of a file that is not Elixir no longer parses the replacement as Elixir, which is how a
  `flake.nix` with `'';` and a comment after it hit the same crash.

## 0.8.0

- `edit --then` at the CLI exits non-zero when the `then` is red: `menard edit --then check … &&
  git commit` committed on a red gate, the reply saying `ok: false` and the exit 0.
- `run test FILE:LINE` names what the line ran in `ran`, green as red: ExUnit takes the closest test
  at or before the line, and a line that has drifted runs another.
- `Menard.Lang`: a Lua row (`luac`, `stylua`). A script with no extension goes by its shebang, and a
  `.sh` of zsh's or fish's is left alone, where `bash -n` refused its syntax.
- Nix: `nil diagnostics` lints what is unused (a binding, a `with`), which neither the parse check
  nor `statix` says.
- A file of these languages written by a shell command gets the same check as a write tool's, by
  name: a script with no extension that a shell command wrote is not covered.
- A tool not installed is named: `skipped` in a verb's reply, once a session from the hook.

## 0.7.0

Nix and shell get what a write does for Elixir (`Menard.Lang`, `docs/scope.md`):

- `.nix`, `.sh` and `.bash` are parse-checked, formatted and linted on the lines changed
  (`nix-instantiate`, `nixfmt`, `statix`; `bash -n`, `shfmt`, `shellcheck`). `edit` and `write`
  refuse what does not parse; the write tools' hook names it. A tool not installed is skipped.
- A formatter leaves alone a file not in its style at HEAD: one line's edit stays one line.
- `run` and `then`: in a repo with no `mix.exs`, `check`, `test` and `compile` run its mise task of
  that name, where they answered with mix's own refusal.
- `outline` on a file that is not Elixir says so, where it read as if the file were broken.

## 0.6.6

- `edit`: a refused batch is kept for `--retry` however deep the project's path. The kept file was
  named by the whole path, encoded, and past a file name's 255 bytes the refusal was "file name
  too long".
- `bin/release VERSION "SUMMARY"` makes a release in one command. The installed plugin follows
  main, and `claude plugin update` goes by the version, so a release is what ships.

## 0.6.5

- The session-start note on piped test runs now says `menard …` itself runs bare: its reply piped
  into a filter is refused, not rewritten. Agents had piped menard and met the refusal.

## 0.6.4

- A session's end removes its marks from `TMPDIR` (a SessionEnd hook); a resumed session writes
  them back. Headless sessions, ~100 an hour, had left two files each for the week's sweep.
- `format`: mise's reason line is read uncoloured; under the gate the reply kept the file's
  drawing instead.

## 0.6.3

Every proposal still open from the review of 2026-10-01 (`docs/review/2026-10-01-fable.md`):

- Under the hooks server credo runs off the call's path; its notes come with the session's next
  answer. At the CLI door, with the call, as before.
- A refused `edit` names which edit of the batch; the batch is kept, and `menard edit --retry N -`
  takes that one again, corrected, with the rest as they were.
- `run check`: every failure a flake under a precommit alias, the alias's outcome is read from
  mix's trace (its steps after the tests ran; one that failed is named), and a test task that
  stops the alias has its steps after it run here. No "run check again".
- `rename Mod.fun new FILES` renames that module's function alone: its heads in `Mod`, and the
  calls that resolve to it (aliased, imported, `__MODULE__.fun`, bare inside `Mod`).
- A `find calls` hit names the function it sits in (`in`), on the CLI line too.
- `clause visibility … private` names the callers in other files it leaves, as `delete` does.
- A session's start puts menard's bin on its PATH (through `CLAUDE_ENV_FILE`), and every text
  then names it `menard`, not its absolute path.
- `block add` in a file of several modules, none named: the one holding the `in` block.
- `map` leaves the root's own `tmp/` out: this repo's bin tests left 241 MB of checkout copies
  there, and map walked them all.
- The skill's description no longer sends an agent to it for a guard that is gone.

## 0.6.2

- A refusal of any kind (a shell command, a subagent sent for a function's callers, a module
  Read again unchanged) is the one that carries the start-of-session text; 0.6.1 told it on a
  shell command's refusal alone.
- `find calls Mod.fun` finds a bare `fun(…)` in a module that imports `Mod` (bare, or with an
  `only:`/`except:` that takes it); it found nothing for `Menard.Verbs.edit` under
  `import Menard.Verbs`.
- The suite: the ten bin/menard tests on a checkout copy or a host project run async in modules
  of their own (220 s of the serial half); the identity oracle makes its edits in parallel; the
  leak check gives a warm host VM its watchdog's three polls.

## 0.6.1

- Compiles without a warning under Elixir 1.20: three branches its type inference proves dead
  (`scripts.ex`, `run.ex`, `clause.ex`) are gone. A host on 1.20 with `--warnings-as-errors`
  could not build 0.6.0 as a dep. The gate compiles under 1.20 too now.
- A session's first refused shell command carries the start-of-session text (no scripts in
  another language, replies read whole): a session that started before the plugin was enabled
  under it, or was resumed from before, had learned the rules one refusal at a time.

## 0.6.0

**From the transcripts** (`docs/review/2026-10-19-transcripts.md`: every session 09-25 to 10-20)
- `edit`: a second search/replace block for the same file needs no path line of its own; at
  the CLI `--then test FILE… -` runs those tests, as the MCP door's `then: "test FILE…"` did.
- A flag the usage lists fills the argument of that name: `write FILE --code CODE`.
- An MCP call the schema refuses says what the tool takes and what was given, where it said
  `edit: edits: ; edits:` for `search`/`replace` in place of `old`/`new`.
- menard's reply through a filter is refused under `timeout`, `time` and the other wrappers.
- `--frozen` runs a module a compile that failed inside a verb (`run compile`,
  `--then compile`) had deleted: the last good build of menard's own modules is kept.
- mise 2026.10 runs an untrusted config: the formatter's reply keeps mise's own reason line
  for the refusal it still makes (a config it cannot parse); the gate's leak check gives a
  warm host VM its watchdog's three polls before counting it.

**One menard, no settings**
- `MENARD_SCRIPTS` and `MENARD_RUNS` are gone: what `full` and `rewrite` did is what menard does.
  No python, perl, ruby or node; a piped test run is run through `menard run`. A ban that was off
  by default was one no session met.
- Reading code a verb reads exactly is refused with that call: `grep "def NAME" -A N` and
  `sed -n '/def NAME/,/end/p'` (clause get), a `sed -n 'N,Mp'` that is one function or test (clause
  get, block get), `grep "Mod.fun"` (find calls), one test or describe by its label with `grep -A`
  (block get), a subagent sent to find a function's calls (find calls), a module Read whole again
  (answered with what changed since the last Read, or that nothing did),
  a file's structure listed or counted (`grep -n 'test "'`, `grep -c "def "`: outline). Only under
  lib/ and test/; any other grep runs, and a program the project tracks may run.
- `find calls` takes a module by the end of its name (`Piped.on?` finds `Menard.Piped.on?`).
- `block add --tag tmp_dir` writes `@tag :tmp_dir`: a bare name is the tag.

**Tests, as the functions are**
- `block move`: tests and describes into another test file, as `clause move` takes functions: their
  `@tag` lines and comment, the private helpers only they call, the attributes and alias/import
  lines they use; a created file gets the source's `use` and `setup`. A helper a staying test
  calls too is refused (a test calling into another test module fails when its file runs alone).
- `outline` of a test file lists its setups, tests and describes with their lines; `where
  FILE:LINE` names the test a line is in; `block list` no longer names a `for` inside a test.
- `edit` puts a function added under a clause after the function's last clause, and says so
  (`moved`), where it refused and told the caller to.
- Replies are written `ok`/`did` first and the version hash last.
- Fixed: cutting two spans whose blank lines touch, the last just above a module's `end`, took the
  `end` (`clause move`/`block move` of a function and the helper under it).

**The Elixir language server**
- The plugin wires expert into Claude Code's `LSP` tool (`lspServers`), through `bin/lsp`, the one
  place that names the server: `MENARD_LSP` swaps it (`expert`, `elixir-ls`) for Claude Code and
  menard alike. It needs expert with #907: v0.1.10 stops answering once Claude Code rejects its
  `registerCapability` (expert #904).
- `find calls Mod.fun` asks the server too, which the MCP server keeps warm (`Menard.Lsp`): a call
  through an `import`, a `defdelegate`, a `use` or an `apply` comes back as `kind: reference`, and
  `lsp` says what answered, or that the hits are the AST's alone (starting, indexing, the CLI).

**One plugin, its hooks inside the server**
- `manos` is merged into `menard`: one Claude Code plugin, the hook, the MCP tools and the skill.
  The tools are `mcp__plugin_menard_menard__<tool>`, and load on demand (no `alwaysLoad`): a
  session starts ~440 tokens larger with the plugin, against ~4,700 with the schemas up front.
- The format hook is `Menard.Hook`, reached by `mcp_tool` hooks in the server already running, and
  the host's formatter is kept warm, one VM per project (`Menard.Format.Worker`): 6-9 ms a write
  once warm, from 0.8-1.0 s. `menard hook` is the same hook for a harness that can only run a
  command; `hooks/format-report.sh` calls it.
- `edit`: replacements of text, several in a file and in several files, in one call, all written
  or none, `then` a run verb after. What a capable model writes a Python heredoc for (in the
  eval's traces its usual way of editing Elixir), whose `replace` says nothing when the text is
  not there: `edit` refuses, and says which. The CLI reads search/replace blocks from stdin. A
  script that edited a module is told of it by the hook, once a session, after the fact; so is
  the third Edit of a run of them. Both name this menard by its path: a plugin's `bin/` is the
  last place a shell looks, and a bare `menard` is whichever one the PATH holds before it.
- `clause split`: a module into several in one call, `plan` a `{to, functions, as?, moduledoc?}`
  per new module, all written or none, delegates left unless `delegate: false`. On ex_riverside's
  862-line `events.ex`: 34 functions and 19 helpers into three modules in one call, where `clause
  move` took a call per module with fix-ups between.
- A noun is declared once (`Menard.Verbs.Noun`, `noun/0` in each verb module), and the MCP tools
  and the editing nouns' mix tasks are generated from it. The CLI's usage is made from the same
  shapes, and every field is also a flag.

- No write puts a function between the clauses of another, where they were together: it parses,
  and a build with warnings as errors fails.
- `edit`'s reply is each file's version and what the formatter changed: what the caller wrote is
  not said back.

**Fixed**
- `clause insert_at` with `top` landed between the first definition and the `@doc`/`@spec` above
  it, which then described the new function.
- `clause move` and `clause split` took a call that leaves a default argument out (`record/4`, of
  `record(a, b, c, d, e \\\\ :x)`) for no function of the module: the helper neither went along nor
  was made public, and the new module did not compile.
- The format hook missed a file a shell command wrote within the second of its mark, and took one
  written just before it for the command's.

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
  function also calls stays, made public (`published`), and the moved code calls it there; one
  named in the move is refused, naming both. `moduledoc` gives a created
  module its `@moduledoc`. The reply adds `moved`, `carried`, `attributes`, `directives`,
  `qualified`, `delegated`, `published` and `left` (without `delegate`, each call now pointing at nothing). In
  riverside1 every agent split ex_riverside's 860-line `events.ex` with a Python script copying
  line ranges and then hand-wrote ~50 delegates; the same split is now three moves and two
  `visibility` calls the first refusal asks for, and it passes step 03's check (grader, credo
  --strict, the API test, the suite). The guard's refusal and the skill say a split is one call
  per new module.
- `deps`: a head's defaults and guard count as what a function calls and reads (they travel with it).

**Fixed**
- The stop gate never checked what manos' MCP tools wrote: its list of projects was the format
  hook's, fed by Edit, Write and Bash, so a session that edited only through menard's tools stopped
  unchecked. A write through them (any verb but `get`, `list` and `refs`) now puts its project on
  the list.
- The stop gate re-checked, at every step (12s), what the agent had just checked itself: in
  riverside1 it never refused a stop. A gate the agent runs (`mix precommit`, `menard run check`)
  whose output is green, nothing red in it, now counts as the stop gate's own green.
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
- `clause move --delegate` copied a default into the delegate as written, where it is evaluated in
  the source: one calling code that moved (`opts \\ defaults()`) called nothing. Such a function
  gets a delegate per arity, each to the same arity, whose default is evaluated where it went.
- `clause move` copied every import without `only:` whenever the moved code made a call nothing
  defined, which a `use`-provided function looks like too: the destination gained an import it
  did not use, which warns. Such an import goes only when it is the one directive that could
  answer the call; otherwise none is copied and the reply's `unresolved` names the call and the
  `use`/`import` lines it may come from.
- `directive remove` of one member of `alias A.{B, C}` was refused, so `clause move` left a member
  only the moved code used in the source, where it warns. The line is rewritten with the others
  (`alias A.C` when one is left).

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
