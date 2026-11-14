# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- `test/menard/run_flake_test.exs:45` failed once in a full suite (2026-11-14, 199 s, the box loaded
  by a gate beside it) and passed on the re-run: `bin/menard run --repeat-until-failure 5`'s answer
  had no `runs` (nil, 2 expected). Run log: `/tmp/menard-run/home-andrew-projects-menard-eb4ec761/
  20261114T182741377485-test.log`.
- The MCP `run` tool takes an unknown key without a word: `{"verb": "test", "files": [...]}` (the
  key is `args`) ran the whole 200 s suite. A key the schema does not name should be refused, and
  the refusal should name the keys it takes; check every tool, not only `run`.

- `test/menard/mcp_replaced_test.exs:37` failed once in a full `run check` (2026-11-11, load ~5) and
  passed on the gate's own re-run: the hooks server was gone when hook 4 was sent, after hook 3 was
  answered and while the install was being put back (`rm_rf` then `cp_r`), with no call in flight.
  So a server can die mid-reinstall, the case the test is for. Not reproduced in 13 runs alone or 6
  beside the door, bin and hook tests. The test now keeps the server's stderr and prints it when
  the server is gone: read that at the next sighting.
