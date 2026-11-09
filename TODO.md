# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- `rename` decides whether `alias Old` binds the bare `Last` per file, not per module: a file of two
  modules, one with `alias Acme.Billing` and one with `alias Acme.Reports.Billing`, has the second
  one's `Billing.x` calls renamed too.
- Flaky under load (machine at load 50-70, 2026-11-09 gate): edit_then_test.exs:39 (`then: test`,
  two host mix runs under the 60 s default timeout) and hooks_test.exs:1144 (compaction reread,
  pure file state, so load alone does not explain it). Each passed on the gate's rerun; the failure
  messages were rotated out of /tmp/menard-run before they were read. Next sighting: keep the log.
