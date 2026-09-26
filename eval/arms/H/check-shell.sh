#!/usr/bin/env bash
# Arm H, the shell side: a model that edits with sed or a heredoc never triggers the Edit/Write
# hook (bench5 change-signature.H.sonnet ended unformatted that way). Before a Bash command, a
# mark; after it, every Elixir file newer than the mark is formatted, and one that does not parse
# is named to the agent. Silent when all is well.
set -uo pipefail

payload=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$payload")
session=$(jq -r '.session_id // "none"' <<<"$payload")
dir=$(jq -r '.cwd // empty' <<<"$payload")
dir=${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}
mark="${TMPDIR:-/tmp}/menard-h-shell-${session//[^A-Za-z0-9_-]/}"

if [[ "$event" == "PreToolUse" ]]; then
  touch "$mark"
  exit 0
fi
[[ -f "$mark" && -f "$dir/mix.exs" ]] || exit 0

changed=$(find "$dir" \( -name _build -o -name deps -o -name .git -o -name node_modules \) -prune -o \
  \( -name '*.ex' -o -name '*.exs' \) -newer "$mark" -print 2>/dev/null)
[[ -n "$changed" ]] || exit 0

problems=""
while IFS= read -r file; do
  # </dev/null: mix reads stdin, and took the rest of this loop's file list with it (only the first
  # of six files a sed changed was formatted)
  out=$("$CLAUDE_PLUGIN_ROOT/bin/menard" run format --in "$dir" "$file" 2>/dev/null </dev/null)
  [[ "$out" == *'"ok":true'* ]] && continue
  why=$(printf '%s' "$out" | jq -r '.failures[0].message // empty' 2>/dev/null | sed 's/; mix format failed:.*//')
  problems+="${file#$dir/} was written but ${why:-could not be formatted}"$'\n'
done <<<"$changed"

[[ -z "$problems" ]] && exit 0
printf '%s' "$problems" >&2
exit 2
