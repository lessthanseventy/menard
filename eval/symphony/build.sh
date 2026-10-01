#!/usr/bin/env bash
# The template a Symphony run starts from: openai/symphony's Elixir project (elixir/ in the repo, its
# own mise.toml, AGENTS.md and Makefile) at the case's base (the parent of its first step's commit),
# without the repo's history or remote (an agent's `git log` would read the commits it is asked to
# make), deps fetched and compiled in dev and test. Its suite once, offline: 299 tests, 6 skipped
# (the live end-to-end ones, which need Linear and Codex).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=${SYMPHONY_SRC:-https://github.com/openai/symphony}
base=$(cat "$here"/cases/*/base)
case "$TEMPLATE" in *[Mm]enard*) echo "build: the work directory's path names menard ($TEMPLATE); set MENARD_EVAL_WORK to a path that does not" >&2; exit 1 ;; esac
clone=$(mktemp -d)
git clone -q "$src" "$clone/repo"
git -C "$clone/repo" checkout -q "$base"
cp -a "$clone/repo/elixir" "$TEMPLATE"
rm -rf "$clone"
cd "$TEMPLATE"

# the eval's wall, the same in every arm (eval/riverside): no network but the package hosts, writes
# in the workspace and the toolchain's caches
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

export MISE_TRUSTED_CONFIG_PATHS="$(dirname "$TEMPLATE")"
mise exec -- mix deps.get >/dev/null
mise exec -- mix compile >/dev/null
MIX_ENV=test mise exec -- mix compile >/dev/null
out=$(mise exec -- mix test 2>&1) || out=$(mise exec -- mix test --failed 2>&1) \
  || { echo "$out" | tail -30; echo "build: the template's own tests are red" >&2; exit 1; }
echo "$out" | tail -1
rm -rf _build/test/lib/symphony_elixir/.mix/.mix_test_failures
echo "template at $base"
