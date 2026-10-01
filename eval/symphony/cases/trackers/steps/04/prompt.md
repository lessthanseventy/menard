Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 4: Jira honors blocking links**

The Jira adapter normalizes every issue with `blocked_by: []` and `dispatchable: true`, so Symphony can start a To Do issue while the issue blocking it is still open. Linear already gates Todo work on its blockers; Jira should do the same, in `SymphonyElixir.Jira.Client`.

- Request the `issuelinks` field in both the candidate search (`/rest/api/3/search/jql`) and the by-id bulk fetch (`/rest/api/3/issue/bulkfetch`), so a refresh right before dispatch sees current blockers.
- A link counts as a blocker when its type name is `Blocks` (ignoring case and surrounding whitespace) and it carries an `inwardIssue`. Outward Blocks links and other link types are ignored. Blockers from other projects count.
- Each blocker becomes `%{id: ..., identifier: ..., state: ...}` in `blocked_by`, in link order: the linked issue's `id`, its `key`, and its `fields.status.name`. Any of these missing or blank is `nil` (a link with only an id gives `%{id: "20005", identifier: nil, state: nil}`).
- `dispatchable` is false only when the issue's own status is `To Do` or `Todo` (ignoring case and whitespace) and some blocker's state is not one of the tracker's `terminal_states` (from the tracker settings passed to the client, compared ignoring case and whitespace). A blocker with unknown state is not terminal. Issues in any other status stay dispatchable whatever their links.
