# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- Flake, not reproduced: the first `menard run check` after editing lib/menard/run.ex (2026-09-26 ~02:13)
  answered green with 15 warnings "redefining module Menard.MCP.Block (current version loaded from
  _build/dev/lib/menard/ebin/…)" at lib/menard/mcp/tools.ex:700/800/861 (Block, Deps, Module). Three runs
  after (mix precommit direct, run check, each precommit stage alone) had none. Suspect bin_test's
  fresh_build! rebuilding the dev build while the edited build was loading.
- `identity_test` "lib/menard/clause.ex stmt replace with a statement's own text" timed out at
  ExUnit's 60s twice under the full gate (2026-09-26 ~04:45 and ~05:08, load average ~40 from
  parallel agents) and passed alone (320 identity tests green) and in the next gate. It is the
  slowest identity case; it has no margin under a loaded machine.
