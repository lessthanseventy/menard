You are working in a checkout of tlon made for this one task. Its live service, databases and
logs are out of reach from here: systemctl and journalctl are stubbed, and the running node will
not answer. Work the ticket below to done: the change made, tests that cover it, and the gate of
the app you changed passing (`cd server && mix precommit`; if you change console too, its `mix precommit` as well).

Ticket #2: Coworker panes have no mise on PATH (Server.Tmux.boot_script)

A pi coworker's bash reported `mise: command not found` in its worktree (#80), so it could not find mix; tlon memory pass then banked facts 133/135 claiming mise is not installed. boot_script should export the operator profile PATH (the unit's PATH fix did this for the service, not for the panes). Repro with a test on boot_script's exports.
