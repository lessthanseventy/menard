# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `hooks_test` "format-elixir formats a file in a host whose mix.exs does not parse" failed
      once under the full gate (2026-09-25) and never alone (7 runs, including with a stale build
      and the guard tests beside it). The hook runs `bin/menard` unfrozen and swallows its
      failure; the gate's log showed "Waiting for lock on the build directory" from tests calling
      `bin/menard` while the suite compiles. Unconfirmed: that a lock wait or a concurrent
      self-compile failed the hook's format.
      Ruled out (2026-09-25, not reproduced by any): the VM cwd a timed-out format left behind
      (fixed; the hook still formats at a 231-char host path and run from the leaked cwd), and a
      stale dev build (hooks_test green with lib touched).
