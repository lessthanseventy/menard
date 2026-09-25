#!/usr/bin/env bash
# Wire menard into Claude Code via its plugin marketplace. menard's .claude-plugin/ already
# declares everything — the MCP server (plugin.json mcpServers), the hooks (hooks/hooks.json:
# the guard, format-on-save, the mix-test nudge), and the skill — so installing the plugin is
# the whole job. No host repo required.
#
# `mise run install:claude` from menard's root, or `scripts/install-claude.sh` directly.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Claude Code's plugin CLI (if the `claude` binary is on PATH). The marketplace is menard's own
# .claude-plugin/marketplace.json; the plugin is menard@menard.
if command -v claude >/dev/null 2>&1; then
  echo "Adding menard marketplace and installing the plugin…"
  claude plugin marketplace add "$repo"
  claude plugin install menard@menard
  echo ""
  echo "menard installed. Restart Claude Code (or /resume) to load the hooks and MCP server."
  exit 0
fi

# No `claude` CLI — print the TUI commands. They work in any Claude Code session.
cat <<EOF
menard is a Claude Code plugin. From a Claude Code session:

  /plugin marketplace add $repo
  /plugin install menard@menard

That gives you:
  • the MCP server (menard's verbs as tools)
  • the PreToolUse guard (Edit/Write on an .ex/.exs module is blocked)
  • format-on-save (menard's formatter on what you write)
  • the skill (skills/menard/SKILL.md — which verb for which change)

Restart Claude Code (or /resume) after installing.
EOF