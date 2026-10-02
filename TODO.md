# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.












- bin_test.exs's `--frozen still runs the last good build` failed once in a full gate with its
  checkout copy's bin/menard missing (`:enoent` at System.cmd), 2026-10-01, while a second session
  edited and gated the same checkout; green alone. Its sibling's failure that run (a deleted
  _build/bintest dep) was the two gates racing, which one check at a time per project now stops.
  Whether a file can go missing from `git ls-files` to the copy without a second session: unknown.
