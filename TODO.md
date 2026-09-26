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
- `find_test`, `run_test` and `hooks_test` still name scratch dirs `System.tmp_dir!()/menard-X-N`
  with N from `System.unique_integer`, which restarts in every VM: test runs in two checkouts at
  once (the review's agents, 2026-09-26) share `/tmp/menard-X-1…` and one's `on_exit` removes the
  other's dir mid-test (mcp_test failed that way, three different tests, until its dirs took the
  OS pid). Add `System.pid()` to each name, as mcp/outline/host_toolchain/format_shell tests do.
- A write whose host formatter cannot run answers a crash dump for the reason. `clause move` in a
  Tlön copy whose mise.toml was not trusted (the eval bench, 2026-09-26): the file was moved, and the
  reply said `not formatted — no match of right hand side value: {:EXIT, {:badarg, [{:erlang,
  :binary_to_atom, [<<69, 108, 105, …` (the formatter's error text made into an atom?), where "mise:
  config files in …/mise.toml are not trusted" was the reason. The eval's agent_env.sh sets
  MISE_TRUSTED_CONFIG_PATHS, so a run does not hit it; a checkout run by hand does.
