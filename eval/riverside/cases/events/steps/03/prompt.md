Last: `lib/ex_riverside/events.ex` has grown to about 860 lines, and it is time to split it. Pull
its parts out into modules of their own under `lib/ex_riverside/events/`, each one coherent (the
listings and queries, the series and their occurrences, the review and lifecycle transitions, or
whatever seams you find are real), so that `ExRiverside.Events` keeps what ties the parts together.
Behaviour stays exactly the same: every public function of `ExRiverside.Events` keeps working as
it does now, from the same module, and the suite stays green.
