menard: SessionEnd removes the session's marks without starting menard

Closes ticket #565. SessionEnd cleanup existed but ran `bin/menard hook` (~2 s BEAM start); a headless
session cuts that hook short, so ~7.7k `menard-told/path-*` marks piled up in /tmp. `hooks/session-end.sh`
is now a plain `rm` of the session's marks.

Checked: new test (a plugin root whose bin/menard hangs; the session's marks must still go, another
session's stay) fails on the old script, passes on the new; `menard run test test/menard/hooks_test.exs`: 33 tests, 0 failures.
Full `run check` not run here.
