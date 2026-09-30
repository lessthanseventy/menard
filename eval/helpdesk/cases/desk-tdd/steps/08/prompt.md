The same way of working as for every ticket: spec, plan, failing tests first, implement, refactor, the gate.

**Ticket 8: who moved it**

The record of a ticket's moves has to say who made each one.

- `Desk.Tickets.transition/2` becomes `Desk.Tickets.change_status/3`: `change_status(ticket, to,
  actor)`, the same rules and the same returns. `actor` is required: `{:agent, agent_id}`,
  `:requester` or `:system`. `transition/2` is gone: nothing defines it and nothing calls it.
- Events gain `actor` (a string): `"agent:<id>"`, `"requester"` or `"system"`. Every event has
  one:
  - a move through `change_status/3`: the actor given;
  - a move a comment made: the comment's author;
  - `"created"`, and what `assign/2`, `unassign/1`, `auto_assign/1` and `deactivate_agent/1`
    record: `"system"`.
- `POST /api/tickets/:id/transition` takes an optional `"agent_id"`: with it the actor is that
  agent, without it `:system`.
- The buttons on the ticket's page move it as `:system`.
