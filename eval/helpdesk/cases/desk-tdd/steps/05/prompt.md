The same way of working as for every ticket: spec, plan, failing tests first, implement, refactor, the gate.

**Ticket 5: response targets**

We promise a first response within a time that depends on priority, counted in business hours:
Monday to Friday, 09:00 to 17:00 UTC. There are no holidays.

Module `Desk.SLA`:

- `target_minutes(priority)`: `:urgent` 60, `:high` 240, `:normal` 480, `:low` 1440.
- `add_business_minutes(datetime, minutes)` returns the `DateTime` (UTC) that many business
  minutes after `datetime`. Time outside business hours does not count: from Saturday noon, or
  from 20:00 on a weekday, the count starts at the next opening. A result that falls exactly at
  closing time is 17:00 that day, not 09:00 the next. `minutes` is a non-negative integer; seconds
  of `datetime` inside business hours are kept.
- `due_at(ticket)`: `add_business_minutes(ticket.inserted_at, target_minutes(ticket.priority))`.
- `breached?(ticket, now)`: true when the first response came after `due_at`, or when there is
  none yet and `now` is after `due_at`.

In `Desk.Tickets`:

- `list_breached(now)` returns the tickets that are breached at `now` and are `:new`, `:open` or
  `:pending`, the one due earliest first.
