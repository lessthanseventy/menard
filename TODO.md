# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- eval/tlon/cases/focus3's planted bug (setup.sh: the fuzzy filter's `score > 0` floor) is caught by
  Tlön's own suite: console/test/console/picker_test.exs:82 ("the palette's corpus finds a verb by
  what it DOES") goes red with the plant and green without (checked 2026-09-26 on the hidden-menard
  template). setup.sh says the plant slips past Tlön's tests; it does not, so both arms start on a
  red test that points at the fault, and step 1 is no misdirection. Re-plant so the project's own
  suite stays green and only the hidden tests catch it, then re-validate the step 1 grader.
- tlon pins menard 0.5.0 from hex (server/mix.lock), and `server/lib/server/source/tools.ex:56`
  hands `Menard.Clause.replace_body/5` whatever its caller gave as `code`. Since 0.5.0 a whole
  clause given there was taken as a `rewrite`; that fallback is removed (2026-09-26, with the
  prose verbs), so on upgrading tlon must send a whole clause to `Menard.Clause.rewrite/5` itself,
  or the call is refused toward `rewrite`. Not edited from here: tlon's change, when it upgrades.
- Two tests go red under host load (2026-09-26, load average 50-66 from other sessions; the same
  tree green on the next run): `test/menard/mcp_test.exs:182` ("resolving many files costs each
  once", a wall-clock bound: 3.04 s against `< 2_000_000` us) and
  `test/menard/host_format_test.exs:352` ("a format out of time is killed…": the slow plugin never
  wrote its pid file inside the 1 s deadline, so `File.read!(pid_file)` raised). Both measure time
  against the machine, so `run check` is not deterministic on a busy host. Make them load-proof
  (count work rather than time it; tolerate the host dying before it wrote its pid).
- `indented/2` in lib/menard/block.ex and lib/menard/clause.ex (identical copies) prefixes EVERY line
  of the text with the indent: a blank line inside a block or definition comes out as trailing
  spaces, and the lines of a heredoc or multi-line string inside it are shifted, changing the
  string's value. `Menard.Source.reindent/2` already handles both (blank stays blank, literal lines
  stay put); `indent <> reindent(text, indent)` is the likely fix, with a test for each case. Left
  out of the Menard.Source consolidation because it changes behaviour.
- docs/review/2026-09-26-fable.md, Tests, the sites left in files another agent was editing
  (2026-09-26): finding 2 at host_format_test.exs:56 and bin_test.exs:91 (a body inside
  `if mise && installed` is green with zero assertions on a box without them: make it a
  compile-time `@tag skip:`, as run_test/host_mix_test/host_toolchain_test now do); finding 3 at
  mcp_test.exs:318 (a wall-clock bound in an async suite: count work, as diff_test and source_test
  now count reductions); finding 5 (mcp_test.exs:116-120, 241-244, 363-366: three pre-builds and
  11 s of `sleep` to hold stdin open; a Port and `assert_receive` instead); finding 12's
  duplicated comments at mcp_test.exs:227-228 and host_format_test.exs:213-218 (its
  run_test.exs:260-261 site shows no duplicate at this base).
- clause_test.exs still holds 39 `=~` assertions on edited source (replace_body/rewrite
  one-liners, the refusal-adjacent checks). The ones where placement or blank lines could hide a
  diff are whole-output `==` now (and found two blank-line bugs); convert the rest as they are
  touched.
- `run check` gives no `skipped` count: `run test` reads it from menard's ExUnit formatter, but
  `check` runs the host's precommit and reads ExUnit's prose (`gate/4` via `counts/1`), which
  drops `N skipped`. A check whose tests all skipped reads like one that ran them.
- `bin/menard run check` in a fresh worktree: `BinTest` "a verb reading stdin gets it, even when
  menard compiles first" timed out at 60s. The `bintest` build is cold there (every dep compiles
  inside the test), and a second run was green. Give the cold-build tests a timeout that covers a
  cold worktree, or warm the `bintest` build first.
