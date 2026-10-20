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

- The gate compiles under 1.19.4 only: 0.6.0 built as a dep of tlon/server (Elixir 1.20.4,
  OTP 29) warned three times on branches 1.20's type inference proves dead, and the gate had said
  nothing (2026-10-20, fixed in 0.6.1). A `compile --warnings-as-errors` under the newest Elixir
  mise has installed, as one more step of `run check`, would have caught it before hex did.
