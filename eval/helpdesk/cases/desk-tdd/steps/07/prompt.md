The same way of working as for every ticket: spec, plan, failing tests first, implement, refactor, the gate.

**Ticket 7: an API and an export**

Other systems read and file tickets.

JSON, under `/api`:

- `GET /api/tickets` answers 200 with `{"data": [ticket, …]}` in `list_tickets/1`'s order; the
  query parameters `status` and `priority` narrow it.
- `GET /api/tickets/:id` answers 200 with `{"data": ticket}`, the ticket here also carrying
  `"comments"`: its public comments, oldest first, each `{"id", "author_kind", "body",
  "inserted_at"}`. An id that is not there answers 404 with `{"error": "not_found"}`.
- `POST /api/tickets` with `{"ticket": {…}}` answers 201 with `{"data": ticket}`, or 422 with
  `{"errors": {"field": ["message", …]}}`.
- `POST /api/tickets/:id/transition` with `{"to": "open"}` answers 200 with `{"data": ticket}`,
  or 422 with `{"error": "invalid_transition"}` (a status that does not exist is one too).

A `ticket` is `{"id", "subject", "status", "priority", "requester_email", "assignee",
"due_at", "inserted_at"}`: `assignee` is `null` or `{"id", "name"}`, the times are ISO 8601,
`due_at` is `Desk.SLA.due_at/1`.

CSV:

- `GET /tickets/export.csv` answers 200 with content type `text/csv`, every ticket in
  `list_tickets/1`'s order under the header
  `id,subject,status,priority,requester_email,assignee,inserted_at` (`assignee` the name, or
  empty). Lines end in CRLF. A field holding a comma, a double quote or a line break is wrapped
  in double quotes, a double quote inside it doubled; no other field is quoted.
