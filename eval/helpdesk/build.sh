#!/usr/bin/env bash
# The template every helpdesk run starts from: `mix phx.new desk` on SQLite, as the installer leaves
# it (its AGENTS.md and its precommit alias included), plus credo in the gate. No code of the
# eval's: the app is what each session builds, from the same start in both arms. Deps fetched and
# compiled in dev and test, so a run starts warm; the suite run once to show the start is green.
#
# SQLite, so a workspace's databases are files of its own (config/dev.exs and test.exs name them
# relative to the config directory) and no run can reach another's, or the operator's.
set -euo pipefail
# the workspace path is in every agent's cwd: one that names menard tells the arm without its name
case "$TEMPLATE" in *[Mm]enard*) echo "build: the work directory's path names menard ($TEMPLATE); set MENARD_EVAL_WORK to a path that does not" >&2; exit 1 ;; esac

cd "$(dirname "$TEMPLATE")"
mix phx.new "$TEMPLATE" --app desk --module Desk --database sqlite3 --no-mailer --no-dashboard --no-gettext --install </dev/null >/dev/null
cd "$TEMPLATE"
rm -rf .git

python3 - <<'PY'
import sys
from pathlib import Path
def swap(path, old, new):
    s = Path(path).read_text()
    if s.count(old) != 1:
        sys.exit(f"build: {path} no longer holds, once: {old.strip()}")
    Path(path).write_text(s.replace(old, new))
# credo, at its default level, in the gate the installer wrote
swap("mix.exs", '      {:bandit, "~> 1.5"}\n', '      {:bandit, "~> 1.5"},\n      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}\n')
swap("mix.exs", 'precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]',
     'precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "credo", "test"]')
PY
mix deps.get >/dev/null
mix format
mix credo gen.config >/dev/null

# The agent's Bash is sandboxed, as in the other benches: no network but the package hosts, writes
# only in the workspace and the toolchain's caches. The same wall in both arms.
mkdir -p .claude
cat > .claude/settings.json <<'JSON'
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "network": {
      "allowLocalBinding": true,
      "allowedDomains": ["hex.pm", "*.hex.pm", "github.com", "*.github.com", "*.githubusercontent.com"]
    },
    "filesystem": {
      "allowWrite": ["~/.cache", "~/.local/share", "~/.local/state", "~/.mix", "~/.hex"]
    }
  }
}
JSON

mix compile >/dev/null
MIX_ENV=test mix compile >/dev/null
out=$(mix precommit 2>&1) || { echo "$out" | tail -30; echo "build: the template's own gate is red" >&2; exit 1; }
echo "$out" | tail -1
# what that run wrote is no part of the start
rm -f ./*.db ./*.db-shm ./*.db-wal
found=$(grep -rIil menard . --exclude-dir=deps --exclude-dir=_build --exclude-dir=node_modules || true)
[[ -z "$found" ]] || { echo "build: the template mentions menard: $found" >&2; exit 1; }
echo "template: phx.new $(mix phx.new --version | awk '{print $NF}')"
