# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- bin_test.exs's `--frozen still runs the last good build` failed once in a full gate with its
  checkout copy's bin/menard missing (`:enoent` at System.cmd), 2026-10-01, while a second session
  edited and gated the same checkout; green alone. Its sibling's failure that run (a deleted
  _build/bintest dep) was the two gates racing, which one check at a time per project now stops.
  Whether a file can go missing from `git ls-files` to the copy without a second session: unknown.

- `find calls Menard.Verbs.edit lib` found nothing, while every writing verb calls it as `edit(…)`
  under `import Menard.Verbs` (2026-10-01). A local call in a module that imports the target's
  module is a call of it.

- `bin_test.exs:361` ("edit --then at the CLI runs the then") failed twice under the full gate,
  2026-10-07, differently each time (a 60s timeout, then `lib/t.ex: the file is not there` — ENOENT
  on a file the test had just written); 15/15 green standalone both times after. Mechanism found:
  ExUnit's `:tmp_dir` path is deterministic — `tmp/<module>/<test name>`, relative to this shared
  worktree — "appropriate for running tests concurrently" WITHIN one `mix test`, but not across two:
  a second session's `mix test` of the same suite, in this same worktree, computes the identical
  path and recreates it (tmp_dir's setup removes-then-makes it fresh) out from under this one's
  test mid-run. Same class as the entry above, same worktree, this time pinned down to the exact
  ExUnit mechanic rather than left as "unknown" — but still not something to fix by changing
  bin_test.exs itself (every `:tmp_dir` test in this repo shares the exposure); it is the shared
  worktree's, which is tlon's to serialize, not menard's.
