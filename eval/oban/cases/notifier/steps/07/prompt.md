Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 7: notifier exits as error tuples**

Calls that go through the notifier process can exit when it crashes mid-call or times out, so callers wrap them in `try`/`catch` (the insert trigger in `Oban.Engine`, `Oban.Stager`, `Oban.Sonar`, `listen/2` and `unlisten/2` themselves). Handle that once, in `Oban.Notifier`:

- `Oban.Notifier.notify/3` never exits because of the notifier: an exit becomes `{:error, %RuntimeError{}}`, the message naming the exit reason (`"notifier exited with ..."`). The existing `{:error, ...}` for an instance with no notifier running stays.
- `listen/2` and `unlisten/2` still return `:ok` whatever the notifier does: the listener registry is what counts.
- The PG and Postgres notifiers no longer raise when their registered state is gone (the notifier is restarting); they return the same kind of error tuple.
- Remove the callers' own exit handling. The stager, when a global `notify` returns an error, falls back to notifying queues locally, as it does now when notifying fails.

Tests about the listener registry itself belong in a test file of their own for `Oban.Notifier.Registry`, run against the Isolated notifier, rather than in the per-notifier tests.
