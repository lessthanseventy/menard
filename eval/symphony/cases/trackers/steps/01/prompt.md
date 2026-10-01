You are working on Symphony's Elixir service, in this repository. Work comes as tickets, one at a time, in this session. Between tickets the team merges its own version of your last change, and other work lands: the tree you find for a ticket is main as it stands then, not what you left. After each ticket, tests you cannot see are run against the interface the ticket names: keep module names, function names, arities, config keys and return shapes exactly as written. Write your own tests as well. Before you finish: `mix format`, `mix lint`, and `mix test` (there is no network here; the live end-to-end tests are skipped).

**Ticket 1: opt-in labels for dispatch**

Right now any active issue in a polled project gets dispatched. Projects need an explicit opt-in: a workflow should be able to say "only touch issues carrying these labels", and taking the label off should stop work on the issue.

Config: a new `tracker.required_labels` in `WORKFLOW.md`, a list of strings, default `[]`. On load, each label is trimmed and lowercased and duplicates are dropped, first occurrence wins: `[" Symphony ", "SYMPHONY", "JavaScript"]` becomes `["symphony", "javascript"]`. A blank label is kept as `""` (`[" "]` becomes `[""]`), and since no issue has it, it matches nothing. Document the key in `README.md` and `WORKFLOW.md`.

`SymphonyElixir.Linear.Issue.routable?(issue, required_labels)` returns whether this worker may work the issue: `assigned_to_worker` must be true, and the issue must carry every required label. Labels compare ignoring case and surrounding whitespace on both sides. An empty list requires nothing. The Linear client should also trim the label names it normalizes.

The gate applies everywhere routing already applies, with the configured labels:

- dispatch eligibility, and the by-id revalidation just before dispatch (an issue that lost its label comes back as `{:skip, refreshed_issue}`);
- reconciling running issues: an issue that lost a required label has its agent stopped and its claim released, like an issue reassigned away (its workspace is not cleaned);
- reconciling blocked issues: release the block and the claim;
- a retry whose lookup finds the issue unlabeled releases its claim and does not reschedule;
- `AgentRunner` stops continuing turns once the refreshed issue lacks a required label.

Test seams the tests call (`@doc false`, each with a `@spec`, like the existing `*_for_test` functions):

- `Orchestrator.reconcile_blocked_issue_states_for_test(issues, state)` returns the updated state.
- `Orchestrator.handle_retry_issue_lookup_for_test(issue, state, issue_id, attempt, metadata)` runs the retry's handling of a looked-up issue and returns the updated state (not the `{:noreply, state}` tuple).
- `AgentRunner.continue_with_issue_for_test(issue, fetcher)`, where `fetcher` takes a list of issue ids like the tracker's by-id fetch, returns `{:continue, refreshed_issue}`, `{:done, refreshed_issue}` or `{:error, reason}`.
