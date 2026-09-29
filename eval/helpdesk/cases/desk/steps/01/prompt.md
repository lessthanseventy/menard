You are building a small help desk in this fresh Phoenix app (SQLite, the app is `desk`). The work
comes as tickets, one at a time, in this session. After each, an acceptance suite you cannot see is
run against the interface the ticket names: keep module names, function names, arities and return
shapes exactly as written. Write your own tests as well. The project's gate is `mix precommit`.

There is no browser here, and no network but the package hosts: a page is checked by its tests
(`Phoenix.LiveViewTest`), not by starting the server and opening it.

**Ticket 1: tickets**

Support staff need tickets to work on.

Schema `Desk.Tickets.Ticket`, table `tickets`, timestamps of type `:utc_datetime`:

- `subject`: required, 1 to 120 characters once trimmed; stored trimmed
- `body`: required
- `requester_email`: required; one `@` with something on both sides and no whitespace; stored
  trimmed and lowercased
- `priority`: `Ecto.Enum`, one of `:low`, `:normal`, `:high`, `:urgent`; default `:normal`
- `status`: `Ecto.Enum`, one of `:new`, `:open`, `:pending`, `:resolved`, `:closed`; default `:new`

Context `Desk.Tickets`:

- `create_ticket(attrs)` returns `{:ok, %Ticket{}}` or `{:error, %Ecto.Changeset{}}`. `attrs` is a
  map with atom or string keys. A new ticket is always `:new`: a `status` in `attrs` is ignored.
- `get_ticket!(id)` returns the ticket or raises `Ecto.NoResultsError`.
- `list_tickets(opts \\ [])` returns tickets, most urgent priority first (`:urgent`, `:high`,
  `:normal`, `:low`), and within a priority the oldest first (by `inserted_at`, then `id`).
  `opts` may hold `status: atom` and `priority: atom`, each narrowing the list.
