You are working in a checkout of tlon made for this one task. Its live service, databases and
logs are out of reach from here: systemctl and journalctl are stubbed, and the running node will
not answer. Work the ticket below to done: the change made, tests that cover it, and the gate of
the app you changed passing (`cd console && mix precommit`; if you change server too, its `mix precommit` as well).

Ticket #3: Console `m` verb is dead: Author.cycle_model! writes a settings file nothing reads

Since workspace_policy landed, a coworker's model comes from Server.Workspaces.set_policy/3. The cockpit's `m` verb still writes the old settings file. Either route it through set_policy or delete the verb and its hint.
