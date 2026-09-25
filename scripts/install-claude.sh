#!/usr/bin/env bash
# Wire menard into Claude Code via its plugin marketplace. menard's .claude-plugin/ already
# declares everything — the MCP server (plugin.json mcpServers), the hooks (hooks/hooks.json:
# the guard, format-on-save, the mix-test nudge), and the skill — so installing the plugin is
# the whole job. No host repo required.
#
# Per project by default: from an Elixir repo, `mise -C ~/path/to/menard run install:claude` (or
# `scripts/install-claude.sh`) installs into THAT repo's .claude/settings.json, so menard's tools
# load there and nowhere else. `--user` installs it for every project instead.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Claude Code's plugin CLI (if the `claude` binary is on PATH). The marketplace is menard's own
# .claude-plugin/marketplace.json; the plugin is menard@menard.
if command -v claude >/dev/null 2>&1; then
  echo "Adding menard marketplace and installing the plugin…"
  claude plugin marketplace add "$repo"
  if [[ "${1:-}" == "--user" ]]; then
    claude plugin install menard@menard --scope user
  else
    # mise moves into menard's root; the repo it was run from is the project
    project="${MISE_ORIGINAL_CWD:-$PWD}"
    echo "Installing into $project (project scope; --user for every project)"
    (cd "$project" && claude plugin install menard@menard --scope project)
  fi
  echo ""
  echo "menard installed. Restart Claude Code (or /resume) to load the hooks and MCP server."
  exit 0
fi

# No `claude` CLI — print the TUI commands. They work in any Claude Code session.
cat <<EOF
menard is a Claude Code plugin. From a Claude Code session:

  /plugin marketplace add $repo
  /plugin install menard@menard     (choose project scope, from the Elixir repo)

That gives you:
  • the MCP server (menard's verbs as tools)
  • the PreToolUse guard (Edit/Write on an .ex/.exs module is blocked)
  • format-on-save (menard's formatter on what you write)
  • the skill (skills/menard/SKILL.md — which verb for which change)

Restart Claude Code (or /resume) after installing.
EOF