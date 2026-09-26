You are working in a checkout of tlon made for this session. Its live service, databases and logs
are out of reach from here: systemctl and journalctl are stubbed, and the running node will not
answer. Several pieces of work follow, one at a time.

First, a bug report from the operator:

"The go-to switcher (^⇧K) doesn't find a thread by the initials of its title once the thread sits
in a project. `rr` should find 'rail redesign' in Machine · Tlön and shows nothing, though typing
`rail` finds it fine."

Find what's wrong and fix it, with tests that would have caught it.
