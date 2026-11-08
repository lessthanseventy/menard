# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- A VM crashing at boot on a stderr gone: the dumps in ~/projects (OTP 27 and 29, 2026-09 to 10)
  say `io:put_chars(standard_error, "** (EXIT from #PID<0.95.0>) … (ErlangError) Erlang error:
  :terminated …")` failed with "the device does not exist". Which VM, and how its stderr went, is
  unknown: `elixir -e 'raise …'` under `2>&-` or a stderr pipe whose reader is gone exits 1, no dump.
  Reproduce it first; 0.8.4 only moved where the dump goes (`ERL_CRASH_DUMP`, bin/menard).
- `lang`: a script with no extension that a shell command wrote is not checked: `Menard.Hook`'s `newer/2` finds files by name.
