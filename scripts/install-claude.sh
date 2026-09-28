#!/usr/bin/env bash
# Wire menard into Claude Code via its plugin marketplace: the `menard` plugin, its formatting
# hook, MCP tools and skill. No host repo required.
#
# Per project by default: from an Elixir repo, `mise -C ~/path/to/menard run install:claude` (or
# `scripts/install-claude.sh`) installs into THAT repo's .claude/settings.json, so menard's tools
# load there and nowhere else. `--user` installs it for every project instead.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

scope=project
plugins=(menard)
for arg in "$@"; do
  case "$arg" in
    --user) scope=user ;;
  esac
done

# Claude Code's plugin CLI (if the `claude` binary is on PATH). The marketplace is menard's own
# .claude-plugin/marketplace.json; the plugin is menard@menard.
if command -v claude >/dev/null 2>&1; then
  echo "Adding menard marketplace and installing ${plugins[*]}…"
  claude plugin marketplace add "$repo"
  # mise moves into menard's root; the repo it was run from is the project
  project="${MISE_ORIGINAL_CWD:-$PWD}"
  [[ "$scope" == project ]] && echo "Installing into $project (project scope; --user for every project)"
  for plugin in "${plugins[@]}"; do
    (cd "$project" && claude plugin install "$plugin@menard" --scope "$scope")
  done
  echo ""
  echo "Installed. Restart Claude Code (or /resume) to load it."
  exit 0
fi

# No `claude` CLI — print the TUI commands. They work in any Claude Code session.
cat <<EOF
menard is a Claude Code plugin. From a Claude Code session:

  /plugin marketplace add $repo
  /plugin install menard@menard     (choose project scope, from the Elixir repo)

menard formats every Elixir file an edit or a shell command writes, with the project's own
formatter, and tells the agent what changed. Its AST-aware tools are there for a rename across
files, finding callers, reading one function of a big module and splitting one.

Restart Claude Code (or /resume) after installing.
EOF
