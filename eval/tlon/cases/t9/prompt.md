You are working in a checkout of tlon made for this one task. Its live service, databases and
logs are out of reach from here: systemctl and journalctl are stubbed, and the running node will
not answer. Work the ticket below to done: the change made, tests that cover it, and the gate of
the app you changed passing (`cd server && mix precommit`; if you change console too, its `mix precommit` as well).

Ticket #9: server:check logs DBConnection "client exited" from a test that ends while holding a connection

Intermittent since 2026-09-25 09:13: 0-2 lines per gate run like [info] Postgrex.Protocol disconnected: ** (DBConnection.ConnectionError) client #PID<...> exited. Some test (a spawned Task or a process killed mid-query) exits while checked out. Find it (grep the run log for the PID), make it await or allow the connection.
