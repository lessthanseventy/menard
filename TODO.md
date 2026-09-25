# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `hooks_test` "format-elixir formats a file in a host whose mix.exs does not parse" failed
      once under the full gate (2026-09-25) and never alone (7 runs, including with a stale build
      and the guard tests beside it). The hook runs `bin/menard` unfrozen and swallows its
      failure; the gate's log showed "Waiting for lock on the build directory" from tests calling
      `bin/menard` while the suite compiles. Unconfirmed: that a lock wait or a concurrent
      self-compile failed the hook's format.
- [ ] `host_format_test`: two tests ("a plugin that will not load…", "a write the format could not
      finish…") failed once under the full gate (2026-09-25) with `{:EXIT, {:system_limit,
      [{:erlang, :list_to_atom, [PATH]}]}}`, PATH being the "a format out of time…" test's tmp dir;
      never alone (3 runs). One test's leftovers (its timed-out format, or a code path it added)
      reach its neighbours, and something makes an atom of a path over 255 chars. Not found where.
