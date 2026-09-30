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
