# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- `test/menard/mcp_replaced_test.exs:37` failed once in a full `run check` (2026-11-11, load ~5) and
  passed on the gate's own re-run: the hooks server was gone when hook 4 was sent, after hook 3 was
  answered and while the install was being put back (`rm_rf` then `cp_r`), with no call in flight.
  So a server can die mid-reinstall, the case the test is for. Not reproduced in 13 runs alone or 6
  beside the door, bin and hook tests. The test now keeps the server's stderr and prints it when
  the server is gone: read that at the next sighting.
- The door answers only its own checkout's `bin/menard`, so `~/projects/menard/bin/menard` from
  another project boots a VM on every call: 2 s idle against 30 ms for the plugin's `menard`
  (bench, 2026-11-17), and 264 of 292 CLI edits outside this repo since 11-11 were written that
  way, at an 11 s median against 3 s. The operator's instructions named that path, and name bare
  `menard` since; what is left is whether the launcher should hand a verb to the installed
  plugin's `bin/menard` when its version is the checkout's.
