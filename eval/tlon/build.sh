#!/usr/bin/env bash
# The template every Tlön run starts from: a clone of the repo at its HEAD (clean: no worktrees,
# no logs, no uncommitted work), with the deps and builds of the real checkout copied in so a run
# starts warm. Toolchain: Tlön's own (mise.toml pins Elixir 1.20.4 / OTP 29).
set -euo pipefail
src=${TLON_SRC:-$HOME/projects/tlon}
# a copy, not hardlinks: /tmp is another filesystem
git clone -q --no-hardlinks "$src" "$TEMPLATE"
# no remote: an agent's `git push` or `fetch` would otherwise reach the operator's live checkout
git -C "$TEMPLATE" remote remove origin
for app in server console; do
  for d in deps _build; do
    [ -d "$src/$app/$d" ] && cp -a --reflink=auto "$src/$app/$d" "$TEMPLATE/$app/$d"
  done
done
# Tlön's server depends on menard (the library), and the dep ships menard's mix tasks with it: in arm
# A `mix menard.run …` would work and `mix help` would list it. The tasks go, source and beams, so
# the control arm has no menard at all; the library the server calls stays.
rm -rf "$TEMPLATE/server/deps/menard/lib/mix"
find "$TEMPLATE/server/_build" -name 'Elixir.Mix.Tasks.Menard.*.beam' -delete
# menard reaches an agent only through the plugins under test: Tlön's AGENTS.md section telling it
# to edit Elixir with `mise run menard` goes (agents_md.py, with the watcher section), and that task
# refuses. Arm A would otherwise have menard's CLI, and arm B the advice the hook-only design dropped.
python3 "$(dirname "$0")/agents_md.py" "$TEMPLATE/AGENTS.md" "$TEMPLATE/AGENTS.md"
printf '#!/usr/bin/env bash\necho "menard: not available in this checkout" >&2\nexit 1\n' > "$TEMPLATE/scripts/menard.sh"

# Tlön's settings sandbox every Bash call, which is one more wall around the agent; its tests need
# Postgres, whose socket the sandbox refuses (eperm). On Linux only allowAllUnixSockets lets it
# through: the path list (allowUnixSockets) is still refused, tried in a bench.
jq '.sandbox.network.allowAllUnixSockets = true' "$TEMPLATE/.claude/settings.json" > "$TEMPLATE/.claude/settings.json.new"
mv "$TEMPLATE/.claude/settings.json.new" "$TEMPLATE/.claude/settings.json"

export MISE_TRUSTED_CONFIG_PATHS="$(dirname "$TEMPLATE")"
for app in server console; do
  (cd "$TEMPLATE/$app" && mise exec -- mix compile >/dev/null && MIX_ENV=test mise exec -- mix compile >/dev/null)
done
echo "template at $(git -C "$TEMPLATE" rev-parse --short HEAD)"
