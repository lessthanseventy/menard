# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- `test/menard/mcp_replaced_test.exs:37` failed once in a full `run check` (2026-11-11, load ~5) and
  passed on the gate's own re-run: the hooks server was gone when hook 4 was sent, after hook 3 was
  answered and while the install was being put back (`rm_rf` then `cp_r`), with no call in flight.
  So a server can die mid-reinstall, the case the test is for. Not reproduced in 13 runs alone or 6
  beside the door, bin and hook tests. The test now keeps the server's stderr and prints it when
  the server is gone: read that at the next sighting.
