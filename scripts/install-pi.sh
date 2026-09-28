#!/usr/bin/env bash
# Wire menard into pi: the guard extension, the MCP server, and the skill.
# Idempotent — re-running updates the paths without duplicating. No host repo required;
# menard is standalone, and this writes only into ~/.pi/agent/ (or $PI_AGENT_DIR).
#
# `mise run install:pi` from menard's root, or `scripts/install-pi.sh` directly.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pi_dir="${PI_AGENT_DIR:-$HOME/.pi/agent}"
settings="$pi_dir/settings.json"
mcp="$pi_dir/mcp.json"
ext="$repo/pi/extension.ts"
skill="$repo/skills/menard"
bin="$repo/bin/menard"

command -v jq >/dev/null 2>&1 || { echo "install-pi: jq is required" >&2; exit 1; }

mkdir -p "$pi_dir"
[ -f "$settings" ] || echo '{}' > "$settings"
[ -f "$mcp" ] || echo '{"mcpServers":{}}' > "$mcp"

# extensions: prune any prior path under <repo>/pi/ then re-add (idempotent + self-healing
# if the checkout moved). Same prune-then-add pattern ficciones' flake uses for its adapters.
tmp=$(mktemp)
jq --arg ext "$ext" --arg repo "$repo" \
  '.extensions = (((.extensions // []) | map(select(startswith($repo + "/pi/") | not))) + [$ext] | unique)
   | .skills = (((.skills // []) | map(select(startswith($repo + "/skills/") | not))) + [$skill] | unique)' \
  --arg skill "$skill" \
  "$settings" > "$tmp" && mv "$tmp" "$settings"

# mcp: add or replace the menard server. No MENARD_ROOT — pi spawns stdio servers with the
# project as cwd, and menard's root falls back to the caller's directory (File.cwd!/0).
tmp=$(mktemp)
jq --arg bin "$bin" \
  '.mcpServers.menard = {command: $bin, args: ["mcp"]}' \
  "$mcp" > "$tmp" && mv "$tmp" "$mcp"

echo "menard wired into pi:"
echo "  extension:  $ext"
echo "  mcp server: $mcp → mcpServers.menard"
echo "  skill:      $skill"
echo ""
echo "Restart pi (or /reload) to load the extension and connect the server."