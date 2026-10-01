# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.



- A flake in the gate (2026-10-01, after 590c116): `check answers with its failures in the one
  shape` (run_test.exs:345) failed once with `mix compile failed: ** (File.Error) could not get
  current working directory nil` from the host project's mix, and passed alone. Nothing calls
  File.cd; something removed the directory the host's mix stood in mid-run. Same run printed a
  `/tmp/menard-toolchain-*/mise.toml are not trusted` error from another test.

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

- An MCP `edit` of three small writes (eval/run.py, two new settings.json; no `then`) hung past
  120 s and wrote nothing, 2026-10-01 00:50, right after two eval runners were killed (pkill) and
  while the server ran pre-d58e6bc code. Cause unknown: whether the server was busy (a hook call
  queued behind something) or the edit itself stuck.





- bin_test.exs's `--frozen still runs the last good build` failed once in a full gate with its
  checkout copy's bin/menard missing (`:enoent` at System.cmd), 2026-10-01, while a second session
  edited and gated the same checkout; green alone. Its sibling's failure that run (a deleted
  _build/bintest dep) was the two gates racing, which one check at a time per project now stops.
  Whether a file can go missing from `git ls-files` to the copy without a second session: unknown.
