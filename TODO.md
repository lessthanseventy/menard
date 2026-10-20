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


- `bin/menard --frozen edit --then compile` on an edit that broke `lib/mix/tasks/menard.edit.ex`
  (a remote call in a guard, 2026-10-20) left `_build` without that task: the next
  `--frozen edit` said "The task menard.edit could not be found". The compile that failed had
  already removed the beam of the module it could not build, so the last good build was gone for
  that one module. `elixir -e` with `String.replace` got the file back; `--frozen` is meant to.
