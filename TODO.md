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
- Flake, not reproduced: the first `menard run check` after editing lib/menard/run.ex (2026-09-26 ~02:13)
  answered green with 15 warnings "redefining module Menard.MCP.Block (current version loaded from
  _build/dev/lib/menard/ebin/…)" at lib/menard/mcp/tools.ex:700/800/861 (Block, Deps, Module). Three runs
  after (mix precommit direct, run check, each precommit stage alone) had none. Suspect bin_test's
  fresh_build! rebuilding the dev build while the edited build was loading.
- The format hook blocks on files a shell command restored untouched: `git checkout -- eval/long/fixture`
  (a project never built in place: no _build, no deps) answered "lib/shop/cart.ex was written but not
  formatted — [Phoenix.LiveView.HTMLFormatter] will not load from …/_build in this VM" for two files
  already formatted at HEAD (2026-09-26 ~03:00). True, but noise: a file the fallback cannot format
  could still be checked (`--check-formatted` without the plugin, or git saying it matches HEAD).
- `find_test`, `run_test` and `hooks_test` still name scratch dirs `System.tmp_dir!()/menard-X-N`
  with N from `System.unique_integer`, which restarts in every VM: test runs in two checkouts at
  once (the review's agents, 2026-09-26) share `/tmp/menard-X-1…` and one's `on_exit` removes the
  other's dir mid-test (mcp_test failed that way, three different tests, until its dirs took the
  OS pid). Add `System.pid()` to each name, as mcp/outline/host_toolchain/format_shell tests do.
