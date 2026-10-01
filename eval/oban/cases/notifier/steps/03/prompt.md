Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 3: a snooze doesn't consume an attempt**

Snoozing a job (`{:snooze, seconds}` from `perform/1`) bumps its `max_attempts`, while executing has already bumped `attempt`. Backoff is computed from `attempt`, so each snooze skews retry timing. Do what Oban Pro does instead:

- `Oban.Engine.snooze_job(conf, job, seconds)` sets the job `scheduled` at `seconds` from now, rolls `attempt` back by one, and leaves `max_attempts` as it was.
- Each snooze also counts itself in the job's `meta` under `"snoozed"`: `1` on the first snooze, incremented after that. Other meta keys are kept.
- This holds for the Basic and Lite engines (and Dolphin, which shares the behaviour), and for the Inline engine used by `testing: :inline`: a job that snoozes there ends up `scheduled` with its `attempt` rolled back (a fresh job's attempt is `0` afterwards) and the `"snoozed"` count in meta.

Update the snoozing docs in `Oban.Worker`: drop the workaround for compensating backoff, and show that a worker can read `meta["snoozed"]`, e.g. to cancel after too many snoozes.
