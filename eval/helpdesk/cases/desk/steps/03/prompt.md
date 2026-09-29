**Ticket 3: staff and assignment**

Tickets get an owner.

Context `Desk.Staff`, schema `Desk.Staff.Agent`, table `agents`:

- `name`: required. `email`: required, unique whatever its case, stored trimmed and lowercased.
  `active`: boolean, default `true`.
- `create_agent(attrs)` returns `{:ok, %Agent{}}` or `{:error, %Ecto.Changeset{}}`; a taken email is
  an error on `:email`.
- `get_agent!(id)`; `list_agents()` by name, then id.
- `deactivate_agent(agent)` returns `{:ok, %Agent{}}` with `active` false, and takes the agent off
  every ticket of theirs that is `:new`, `:open` or `:pending`. Resolved and closed tickets keep
  their assignee.

Tickets gain `assignee_id` (an agent, or nil). In `Desk.Tickets`:

- `assign(ticket, agent)` returns `{:ok, %Ticket{}}`, `{:error, :inactive_agent}` or
  `{:error, :closed}` (a closed ticket takes no assignee). Assigning a `:new` ticket opens it: it
  becomes `:open`, with the status event that move records. Every assignment records an event of
  kind `"assigned"`, `from` the previous assignee's id as a string or nil, `to` the new one's.
- `unassign(ticket)` returns `{:ok, %Ticket{}}` with no assignee, and records an event of kind
  `"unassigned"`, `from` the assignee's id as a string, `to` nil. A ticket with no assignee is
  returned as it is, with no event.
- `auto_assign(ticket)` assigns the active agent with the fewest tickets in `:new`, `:open` or
  `:pending`; among equals, the lowest id. Returns what `assign/2` returns, or
  `{:error, :no_agents}` when no agent is active.
- `list_tickets/1` takes `assignee: agent_id` (that agent's tickets) and `assignee: :none`
  (tickets with no assignee).
