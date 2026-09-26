You are working in a checkout of tlon made for this session. Its live service, databases and logs
are out of reach from here: systemctl and journalctl are stubbed, and the running node will not
answer. Several pieces of work follow, one at a time.

First, a bug report from the operator:

"Sometimes a Claude Code coworker is plainly waiting for my approval in its window, the permission
dialog right there on screen, but the cockpit never shows it as needing attention and no prompt
appears for it. I think it happens when the highlighted choice in the dialog isn't the first one: I
had moved the selection down to 'Yes, and don't ask again' before switching away."

Find the cause and fix it, with a test that would have caught it.
