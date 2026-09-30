The same way of working as for every ticket: spec, plan, failing tests first, implement, refactor, the gate.

**Ticket 4: comments**

Agents and requesters talk on a ticket, and the conversation moves it.

Schema `Desk.Tickets.Comment`, table `ticket_comments`, timestamps `:utc_datetime`:

- `ticket_id`; `body`: required
- `author_kind`: `Ecto.Enum`, `:agent` or `:requester`, required
- `agent_id`: required when the author is an agent, nil for a requester
- `internal`: boolean, default `false`. Only an agent writes an internal note: from a requester it
  is an error on `:internal`.

In `Desk.Tickets`:

- `add_comment(ticket, attrs)` returns `{:ok, %{comment: %Comment{}, ticket: %Ticket{}}}` (the
  ticket as it is after the comment), `{:error, %Ecto.Changeset{}}`, or `{:error, :closed}`: a
  closed ticket takes no comment of any kind.
- What a comment does to the ticket, each move recording its status event:
  - an agent's public comment on a `:new` or `:open` ticket makes it `:pending` (we are waiting
    on the requester);
  - a requester's comment on a `:pending` or `:resolved` ticket makes it `:open`, and a reopened
    ticket loses its `resolved_at`;
  - an internal note moves nothing.

  These moves are the conversation's, and are not held to the table `transition/2` follows.
- A new ticket field `first_response_at` (`:utc_datetime`): set by the first public comment from
  an agent, and never changed after.
- `list_comments(ticket, opts \\ [])` returns the ticket's comments, oldest first. With
  `internal: false` the internal notes are left out.
