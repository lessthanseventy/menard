#!/usr/bin/env bash
# The template every ex_riverside run starts from: a clone of the repo at its HEAD with no history
# and no remote (an agent's `git log`, `fetch` or `push` would otherwise reach the operator's
# checkout and its past), the deps and builds of the real checkout copied in so a run starts warm,
# compiled in dev and test on the project's own toolchain (mise.toml: Elixir 1.19.4 / OTP 27).
# Nothing secret comes along: mise.local.toml (the AI key) and .env are gitignored, so the clone
# has none, and the suite is run once here to show the app compiles and tests without them and
# without the network (AI_BASE_URL dead, no key).
set -euo pipefail
src=${RIVERSIDE_SRC:-$HOME/projects/ex_riverside}
# the workspace path is in every agent's cwd and in what its tests render (excessibility's
# snapshots carry file:// URLs into _build): a runs directory named after menard tells arm A the
# name. MENARD_EVAL_WORK=/tmp/riverside-eval, not the runner's default.
case "$TEMPLATE" in *[Mm]enard*) echo "build: the work directory's path names menard ($TEMPLATE); set MENARD_EVAL_WORK to a path that does not" >&2; exit 1 ;; esac
# a copy, not hardlinks: /tmp is another filesystem
git clone -q --no-hardlinks "$src" "$TEMPLATE"
sha=$(git -C "$TEMPLATE" rev-parse --short HEAD)
rm -rf "$TEMPLATE/.git"
for d in deps _build; do
  cp -a --reflink=auto "$src/$d" "$TEMPLATE/$d"
done
for f in mise.local.toml .env; do
  [ -e "$TEMPLATE/$f" ] && { echo "build: $f came along with the clone" >&2; exit 1; }
done

# Two lines of config, the same in every arm. The dev database is hardcoded (config/dev.exs); a
# run's `mix ecto.setup` or `mix phx.server` would otherwise land in the operator's
# ex_riverside_dev, so agent_env.sh gets to name one of the run's own (the test database already
# takes MIX_TEST_PARTITION). And the Repo reaches Postgres over TCP (hostname localhost), which the
# sandbox below refuses (probed: a sandboxed `mix test` got econnrefused on localhost:5432); over the
# unix socket it gets through (allowAllUnixSockets, as Tlön's runs need), and pg_hba trusts it.
python3 - "$TEMPLATE" <<'PY'
import sys
from pathlib import Path
t = Path(sys.argv[1])
def swap(path, old, new):
    s = path.read_text()
    if s.count(old) != 1:
        sys.exit(f"build: {path.relative_to(t)} no longer holds, once: {old.strip()}")
    path.write_text(s.replace(old, new))
swap(t / "config/dev.exs", '  database: "ex_riverside_dev",\n',
     '  database: System.get_env("EX_RIVERSIDE_DEV_DB", "ex_riverside_dev"),\n')
for env in ("dev", "test"):
    swap(t / f"config/{env}.exs", '  hostname: "localhost",\n', '  socket_dir: "/run/postgresql",\n')
PY

# The agent's Bash is sandboxed, as in the Tlön bench: no network but the package hosts, writes
# only in the workspace and the toolchain's caches, Postgres through its unix socket (above). The
# repo has no .claude/settings.json of its own: this wall is the eval's, the same for every arm,
# and it is what keeps a run off the operator's databases, network and production.
mkdir -p "$TEMPLATE/.claude"
cat > "$TEMPLATE/.claude/settings.json" <<'JSON'
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "network": {
      "allowLocalBinding": true,
      "allowAllUnixSockets": true,
      "allowedDomains": ["hex.pm", "*.hex.pm", "github.com", "*.github.com", "*.githubusercontent.com"]
    },
    "filesystem": {
      "allowWrite": ["~/.cache", "~/.local/share", "~/.local/state", "~/.mix", "~/.hex"]
    }
  }
}
JSON

export MISE_TRUSTED_CONFIG_PATHS="$(dirname "$TEMPLATE")"
cd "$TEMPLATE"
mise exec -- mix compile >/dev/null
MIX_ENV=test mise exec -- mix compile >/dev/null
# the suite once, on a database of its own, dropped after: a template whose tests are red would
# fail every run's check the same way
export MIX_TEST_PARTITION=_template AI_BASE_URL=http://127.0.0.1:9/v1 AI_API_KEY=
out=$(mise exec -- mix test 2>&1) || { echo "$out" | tail -30; echo "build: the template's own tests are red" >&2; exit 1; }
echo "$out" | tail -1
dropdb -h /run/postgresql --force --if-exists ex_riverside_test_template
# what that run wrote (excessibility's page snapshots, gitignored): not the agent's to find
rm -rf test/excessibility/html_snapshots
echo "template at $sha"
