**Ticket 2: the status flow**

A ticket moves through its statuses by fixed rules, and we want a record of every move.

In `Desk.Tickets`:

- `transition(ticket, to)` returns `{:ok, %Ticket{}}` or `{:error, :invalid_transition}`. Allowed:

  | from | to |
  |---|---|
  | `:new` | `:open` |
  | `:open` | `:pending`, `:resolved` |
  | `:pending` | `:open`, `:resolved` |
  | `:resolved` | `:open`, `:closed` |
  | `:closed` | nothing |

  A move to the status the ticket already has is invalid.
- `allowed_transitions(status)` returns the statuses a ticket in `status` may move to, as a list in
  the order `:open`, `:pending`, `:resolved`, `:closed`.
- Two new ticket fields, `resolved_at` and `closed_at` (`:utc_datetime`, nil until set).
  `resolved_at` is set when a ticket becomes `:resolved` and cleared when it is reopened (goes back
  to `:open`); closing keeps it. `closed_at` is set when it becomes `:closed`.

Schema `Desk.Tickets.Event`, table `ticket_events`: `ticket_id`, `kind`, `from`, `to` (strings,
`from` and `to` may be nil), `inserted_at`.

- Creating a ticket records an event of kind `"created"`, `from` nil, `to` `"new"`.
- Each move records one of kind `"status"`, `from` and `to` the statuses as strings. A refused
  move records nothing.
- `list_events(ticket)` returns the ticket's events, oldest first.
