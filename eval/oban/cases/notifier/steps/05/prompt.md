Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 5: a stale execution can't overwrite a newer one**

When the same job ends up executing twice (an orphan rescued and run again, say), the older execution's ack can land after the newer one finished and transition the job back out of `completed`, e.g. to `retryable` or `scheduled`.

Acking must only touch the execution it belongs to. In the Basic, Lite and Dolphin engines, `complete_job/2`, `discard_job/2`, `error_job/3`, `snooze_job/3`, and `cancel_job/2` for a job carrying an `unsaved_error` (the executor cancelling its own job) apply only when the row is still `executing` and its `attempted_at` is the one on the job struct passed in. Otherwise they change nothing, errors included, and still return `:ok`.

One exception: a job cancelled from outside while it runs (`Oban.cancel_job/2`) is already `cancelled` when the executor's own cancel ack arrives. That ack still applies, so the attempt's error is recorded in the job's `errors`.

`cancel_job/2` without an `unsaved_error` (a cancel from outside) keeps its current behaviour.
