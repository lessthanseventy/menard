Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 6: a retry must not leak its claim at dispatch**

When a retry fires, the orchestrator looks the issue up and, if it is still a candidate and there are slots, dispatches it. Dispatch then refreshes the issue by id once more before starting work. If that second read finds the issue gone, stale or fails, dispatch quietly does nothing: the retry entry is already popped, so the issue stays claimed forever and is never picked up again.

Keep the dispatch-time refresh (skipping it would dispatch stale work), but let the retry act on its outcome:

- refreshed and still dispatchable: dispatch as today;
- not found: release the claim;
- found but no longer dispatchable: handle the refreshed issue as a retry lookup result (terminal: clean up and release; no longer active or routable: release; and so on);
- the refresh errored: schedule another retry (next attempt) with an error describing the failed refresh, rather than dropping the claim.

In every case the issue must end up running, released, or scheduled for retry, never claimed with nothing holding it. `Orchestrator.handle_retry_issue_lookup_for_test/5` exercises this path.
