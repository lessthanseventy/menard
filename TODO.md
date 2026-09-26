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
- `mcp_test`'s root is `menard-mcp-#{System.unique_integer([:positive])}` in /tmp, unique only within
  one VM: two suites run at once (parallel worktrees, 2026-09-26) share small integers, and one's
  `on_exit` `rm_rf` deletes the other's files. Three runs failed three different tests ("could not
  read file /tmp/menard-mcp-1282/lib/a.ex", an attr set that did not land, a block delete refused);
  alone, green. Fix: a root from `System.tmp_dir!()` + a random or OS-pid-qualified name.
- The identity test "lib/menard/clause.ex stmt replace with a statement's own text" takes ~25s alone
  (621 stmt edits, 2026-09-26) and hit ExUnit's 60s timeout in the full suite on a machine at load
  ~30 (20 cores): the corpus grows with clause.ex, and nothing but the default timeout bounds it.
- The format hook blocks on files a shell command restored untouched: `git checkout -- eval/long/fixture`
  (a project never built in place: no _build, no deps) answered "lib/shop/cart.ex was written but not
  formatted — [Phoenix.LiveView.HTMLFormatter] will not load from …/_build in this VM" for two files
  already formatted at HEAD (2026-09-26 ~03:00). True, but noise: a file the fallback cannot format
  could still be checked (`--check-formatted` without the plugin, or git saying it matches HEAD).
