# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- Flake, not reproduced: the first `menard run check` after editing lib/menard/run.ex (2026-09-26 ~02:13)
  answered green with 15 warnings "redefining module Menard.MCP.Block (current version loaded from
  _build/dev/lib/menard/ebin/…)" at lib/menard/mcp/tools.ex:700/800/861 (Block, Deps, Module). Three runs
  after (mix precommit direct, run check, each precommit stage alone) had none. Suspect bin_test's
  fresh_build! rebuilding the dev build while the edited build was loading.
- A write whose host formatter cannot run answers a crash dump for the reason. `clause move` in a
  Tlön copy whose mise.toml was not trusted (the eval bench, 2026-09-26): the file was moved, and the
  reply said `not formatted — no match of right hand side value: {:EXIT, {:badarg, [{:erlang,
  :binary_to_atom, [<<69, 108, 105, …` (the formatter's error text made into an atom?), where "mise:
  config files in …/mise.toml are not trusted" was the reason. The eval's agent_env.sh sets
  MISE_TRUSTED_CONFIG_PATHS, so a run does not hit it; a checkout run by hand does.
