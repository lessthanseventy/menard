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

- The full gate (`mise run check` / `bin/menard run check`, 1074 tests, max_cases: 40) is flaky
  under load: a heavy-AST test (seen: `move_test.exs:10`, 60s `ExUnit.TimeoutError` in
  `Sourceror.Zipper`/`Menard.Find.aliases_in`; previously `bin_test.exs:361`) times out only when
  the full suite runs many cases in parallel — each passes clean alone in seconds. 2026-10-07,
  seen twice on workline menard-lazy-compile-so-a-fresh-install-d with two different tests tripping
  it, on a branch whose own 3 commits don't touch Find/Move/bin. Root cause is CPU contention from
  running the whole suite async, not the branch under test. `hooks_test.exs:499` and
  `lsp_test.exs:74` fail the same gate for separate, permanent reasons (this machine's
  `merge.ff=only` git config; no "expert" LSP server installed) — not flaky, always red here.
