# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

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
- `bin/menard run check` in a fresh worktree: `BinTest` "a verb reading stdin gets it, even when
  menard compiles first" timed out at 60s. The `bintest` build is cold there (every dep compiles
  inside the test), and a second run was green. Give the cold-build tests a timeout that covers a
  cold worktree, or warm the `bintest` build first.
