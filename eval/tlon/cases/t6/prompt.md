You are working in a checkout of tlon made for this one task. Its live service, databases and
logs are out of reach from here: systemctl and journalctl are stubbed, and the running node will
not answer. Work the ticket below to done: the change made, tests that cover it, and the gate of
the app you changed passing (`cd server && mix precommit`; if you change console too, its `mix precommit` as well).

Ticket #6: Ticket → thread from /api, tlon-cli and the MCP tools, not only the cockpit

Server.Tickets.start_thread/1 (2026-09-25) is the verb; only the cockpit's Enter on the ticket board calls it. Add POST /api/tickets/:id/start, a `tlon-cli ticket start ID`, and an MCP tool so a coworker can start a filed ticket. Same door everywhere.
