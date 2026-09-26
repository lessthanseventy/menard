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
