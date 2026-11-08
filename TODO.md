# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- A script that raises with stderr unwritable crashes the VM at boot (Elixir's bug: Kernel.CLI
  prints the exception to stderr, that raises, and its handler's print raises again). Reproduced in
  the operator's terminal (`elixir boom.exs 2>&-`, or `2>&1 >/dev/null | true`), not in a Claude
  Code shell: there a closed fd 2 is reused by the next file opened (the `elixir` launcher), and
  the VM ignores SIGPIPE. The verb's VM writes its stderr to a temp file, so it is exposed only
  where it inherits the caller's: `mcp`, and a sandbox that denies the temp dir. The dump no longer
  lands in a project (0.8.4). Left: a guarded print in bin/menard's `script`, once a test is red
  for it here. Upstream: https://github.com/elixir-lang/elixir/issues/16079
- `lang`: a script with no extension that a shell command wrote is not checked: `Menard.Hook`'s `newer/2` finds files by name.
- The filter refusal says "through a filter" when what it saw was `>/dev/null`: name which.
- A session whose hooks server timed out connecting (30 s under load; three sessions in a month)
  runs with no hooks and no word of it. The SessionStart command hook could say so, once.
