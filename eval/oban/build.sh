#!/usr/bin/env bash
# The template an Oban run starts from: oban-bg/oban at the case's base (the parent of its first
# step's commit), history and remote dropped (an agent's `git log` would otherwise read the very
# commits it is asked to make), on mise's Elixir 1.19.5 / OTP 28 (Oban pins none), deps fetched and
# compiled in dev and test. Its suite once, MySQL's tests left out (`dolphin`: no MySQL here, the
# same in every arm), on the template database every run's own is cloned from (cleanup.sh fresh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=${OBAN_SRC:-https://github.com/oban-bg/oban}
base=$(cat "$here"/cases/*/base)
case "$TEMPLATE" in *[Mm]enard*) echo "build: the work directory's path names menard ($TEMPLATE); set MENARD_EVAL_WORK to a path that does not" >&2; exit 1 ;; esac
git clone -q --no-hardlinks "$src" "$TEMPLATE"
git -C "$TEMPLATE" checkout -q "$base"
rm -rf "$TEMPLATE/.git"
cd "$TEMPLATE"
printf '[tools]\nerlang = "28"\nelixir = "1.19.5-otp-28"\n' > mise.toml

# the eval's wall, the same in every arm (eval/riverside): no network but the package hosts, writes
# in the workspace and the toolchain's caches, Postgres through its unix socket
mkdir -p .claude
cat > .claude/settings.json <<'JSON'
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
mise exec -- mix deps.get >/dev/null
mise exec -- mix compile >/dev/null
MIX_ENV=test mise exec -- mix compile >/dev/null

# the database every run's is cloned from, migrated; SQLite's (priv/oban.db) lives in the tree
export MIX_ENV=test POSTGRES_URL="postgres://localhost/oban_eval_template?socket_dir=/run/postgresql"
dropdb -h /run/postgresql --force --if-exists oban_eval_template
for repo in Oban.Test.Repo Oban.Test.LiteRepo; do
  mise exec -- mix ecto.create --quiet -r "$repo"
  mise exec -- mix ecto.migrate --quiet -r "$repo"
done

# on a clone of it, as a run's tests are; a timing test red under load gets one rerun, as the check
createdb -h /run/postgresql -T oban_eval_template oban_eval_build
export POSTGRES_URL="postgres://localhost/oban_eval_build?socket_dir=/run/postgresql"
out=$(mise exec -- mix test --exclude dolphin 2>&1) || out=$(mise exec -- mix test --failed --exclude dolphin 2>&1) \
  || { echo "$out" | tail -30; dropdb -h /run/postgresql --force oban_eval_build; echo "build: the template's own tests are red" >&2; exit 1; }
echo "$out" | tail -1
dropdb -h /run/postgresql --force oban_eval_build
rm -rf _build/test/lib/oban/.mix/.mix_test_failures
echo "template at $base"
