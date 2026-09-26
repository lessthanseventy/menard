# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- tlon pins menard 0.5.0 from hex (server/mix.lock), and `server/lib/server/source/tools.ex:56`
  hands `Menard.Clause.replace_body/5` whatever its caller gave as `code`. Since 0.5.0 a whole
  clause given there was taken as a `rewrite`; that fallback is removed (2026-09-26, with the
  prose verbs), so on upgrading tlon must send a whole clause to `Menard.Clause.rewrite/5` itself,
  or the call is refused toward `rewrite`. Not edited from here: tlon's change, when it upgrades.
- docs/review/2026-09-26-fable.md, Tests, the sites left in files another agent was editing
  (2026-09-26): finding 2 at host_format_test.exs:56 and bin_test.exs:91 (a body inside
  `if mise && installed` is green with zero assertions on a box without them: make it a
  compile-time `@tag skip:`, as run_test/host_mix_test/host_toolchain_test now do); finding 3 at
  mcp_test.exs:318 (a wall-clock bound in an async suite: count work, as diff_test and source_test
  now count reductions); finding 5 (mcp_test.exs:116-120, 241-244, 363-366: three pre-builds and
  11 s of `sleep` to hold stdin open; a Port and `assert_receive` instead); finding 12's
  duplicated comments at mcp_test.exs:227-228 and host_format_test.exs:213-218 (its
  run_test.exs:260-261 site shows no duplicate at this base).
- `run check` gives no `skipped` count: `run test` reads it from menard's ExUnit formatter, but
  `check` runs the host's precommit and reads ExUnit's prose (`gate/4` via `counts/1`), which
  drops `N skipped`. A check whose tests all skipped reads like one that ran them.
- hooks/format-report.sh:30 skips a Bash command only when it STARTS with `git`: `cd DIR && git
  worktree add …` (or a checkout after a `cd`) is taken for an edit of every file git wrote, and the
  hook formats each one; in a worktree whose eval fixture has no deps fetched, that was ~45
  "Unknown dependency :phoenix" errors back to the agent (2026-09-26). Matching `git` anywhere is
  wrong too (`git checkout x && sed -i a.ex` is a real edit): skip only files git itself wrote, e.g.
  those whose content matches the index/HEAD after the command.
- `bin/menard --frozen` is only as good as `_build`: one verb run WITHOUT `--frozen` while the tree
  does not compile (a half-applied edit) fails the compile, and the compiler has already removed the
  beams of the modules it was recompiling (Menard.Source, Menard.Block, Menard.Clause gone from
  `_build/dev/lib/menard/ebin`, 2026-09-26). Every later `--frozen` verb then dies on "module
  Menard.Source is not available", and the edit has to be finished by hand. A frozen copy of the
  last good build (or compiling into a scratch build path) would keep `--frozen` working.
