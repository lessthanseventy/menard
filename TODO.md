# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- Flake, not reproduced: the first `menard run check` after editing lib/menard/run.ex (2026-09-26 ~02:13)
  answered green with 15 warnings "redefining module Menard.MCP.Block (current version loaded from
  _build/dev/lib/menard/ebin/…)" at lib/menard/mcp/tools.ex:700/800/861 (Block, Deps, Module). Three runs
  after (mix precommit direct, run check, each precommit stage alone) had none. Suspect bin_test's
  fresh_build! rebuilding the dev build while the edited build was loading.
- The format hook blocks on a file its formatter cannot load a plugin for even when the file is
  already formatted: `git checkout -- eval/long/fixture` (a project never built in place) answered
  "lib/shop/cart.ex was written but not formatted — [Phoenix.LiveView.HTMLFormatter] will not load
  from …/_build in this VM" for files formatted at HEAD (2026-09-26 ~03:00). git commands are skipped
  now; any other write of such a file still blocks. It could be checked instead (`--check-formatted`
  without the plugin, or git saying it matches HEAD).
- `identity_test` "lib/menard/clause.ex stmt replace with a statement's own text" timed out at
  ExUnit's 60s twice under the full gate (2026-09-26 ~04:45 and ~05:08, load average ~40 from
  parallel agents) and passed alone (320 identity tests green) and in the next gate. It is the
  slowest identity case; it has no margin under a loaded machine.
- `mcp_test`'s root is `menard-mcp-#{System.unique_integer([:positive])}` in /tmp, unique only within
  one VM: two suites run at once (parallel worktrees, 2026-09-26) share small integers, and one's
  `on_exit` `rm_rf` deletes the other's files. Three runs failed three different tests ("could not
  read file /tmp/menard-mcp-1282/lib/a.ex", an attr set that did not land, a block delete refused);
  alone, green. Fix: a root from `System.tmp_dir!()` + a random or OS-pid-qualified name.
