# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- `run test --slowest N` runs it and drops the report: a green reply is only the counts, so the
  slowest list is only in the log. The reply should carry it (`slowest: [{name, at, ms}]`).

- The gate costs ~2,450 CPU-seconds (measured 2026-09-29, /proc/stat across a run, ~200s wall at
  load 14; 5-10 min when other sessions load the box). Splitting HooksTest and IdentityTest into
  modules made it slower: it is CPU-bound, not serial. The cost to cut is VM starts: tests that
  spawn `bin/menard` (mise exec + a BEAM + mix) or a host formatter per tmp project. Measure per
  module before cutting.


- A Claude Code process started before a change to the plugin's wiring keeps the old wiring, and
  nothing says so. Found 2026-09-30 in a session started 09-26 (kept across `/clear`): no MCP
  server (the plugin had none then, 69059a4; it came back in 3c68c0c on 09-28), so no tools, and
  no hook on Read, Agent or Task; the 09-26 wiring's hooks/format-report.sh, today `menard hook`,
  still answered Bash and Write/Edit. format-report.sh could notice it is run as a command hook
  under Claude Code, which hooks.json no longer does, and tell the agent to restart Claude Code.

- `edit --then test` runs the whole suite (then_run/2 passes no args: 1,034 tests for a one-line
  edit of lib/menard/piped.ex, 2026-09-30), where the skill says to test the changed files while
  working. It should run the tests of what it changed: an edited test file, and the test file
  that mirrors an edited lib file (or `--stale`).
