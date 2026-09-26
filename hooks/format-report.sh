#!/usr/bin/env bash
# PostToolUse on Edit|Write|MultiEdit, and Pre/PostToolUse(+Failure) on Bash: every Elixir file an
# edit or a shell command wrote is formatted with its own project's formatter, plugins included.
# What the formatter changed goes back to the agent as context, so its next Edit is written
# against the file as it is, not as it read it (`999999` became `999_999` under an agent in the
# eval, and its next Edit missed). A file that does not parse is named, with the compiler's why.
#
# The eval (bench5): this alone gave menard's clean output, at no-menard's cost.
set -uo pipefail

payload=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$payload")
tool=$(jq -r '.tool_name // empty' <<<"$payload")
session=$(jq -r '.session_id // "none"' <<<"$payload")
cwd=$(jq -r '.cwd // empty' <<<"$payload")
mark="${TMPDIR:-/tmp}/menard-format-${session//[^A-Za-z0-9_-]/}"

# A shell command: a mark before it, and after it every Elixir file newer than the mark
if [[ "$tool" == "Bash" && "$event" == "PreToolUse" ]]; then
  touch "$mark"
  exit 0
fi

if [[ "$tool" == "Bash" ]]; then
  root=${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}
  [[ -f "$mark" ]] || exit 0
  files=$(find "$root" \( -name _build -o -name deps -o -name .git -o -name node_modules \) -prune -o \
    \( -name '*.ex' -o -name '*.exs' \) -newer "$mark" -print 2>/dev/null)
  # what git ignores is no one's edit: menard's own test run writes fixtures under tmp/, broken on
  # purpose, and each was named as a file the agent wrote and could not format
  # -z: without it git prints a path with a non-ASCII byte quoted and escaped, which matches nothing
  ignored=$(tr '\n' '\0' <<<"$files" | git -C "$root" check-ignore -z --stdin 2>/dev/null | tr '\0' '\n')
  [[ -n "$ignored" ]] && files=$(grep -vxF -f <(printf '%s\n' "$ignored") <<<"$files")
else
  files=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' <<<"$payload")
fi
[[ -n "$files" ]] || exit 0

report="" problems="" moved=""
while IFS= read -r file; do
  case "$file" in *.ex | *.exs) ;; *) continue ;; esac
  [[ -f "$file" ]] || continue
  dir=$(dirname "$(readlink -f "$file")")
  while [[ "$dir" != "/" && ! -f "$dir/mix.exs" ]]; do dir=$(dirname "$dir"); done
  [[ -f "$dir/mix.exs" ]] || continue
  # the Stop hook's list: the projects this session wrote Elixir into, the ones to gate before it ends
  printf '%s\n' "$dir" >>"${TMPDIR:-/tmp}/menard-touched-${session//[^A-Za-z0-9_-]/}"

  before=$(mktemp)
  cp "$file" "$before"
  # </dev/null: mix reads stdin, and inside this loop took the rest of the file list with it
  out=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run format --in "$dir" "$file" 2>/dev/null </dev/null)

  if [[ "$out" == *'"ok":true'* ]]; then
    change=$(diff -U0 "$before" "$file" | grep -v '^---\|^+++' | head -40)
    [[ -n "$change" ]] && report+="${file#"$dir"/} was reformatted:"$'\n'"$change"$'\n' && moved=1
    # credo on what this session changed in the file, when the project lints with it: found at write
    # time it is one edit; found in CI it is a round trip. Its default level; --strict is the project's.
    if [[ -d "$dir/deps/credo" ]] || grep -qs '"credo":' "$dir/mix.lock"; then
      lint=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run credo --in "$dir" --changed "${file#"$dir"/}" 2>/dev/null </dev/null |
        jq -r '.failures[]? | "  \(.at) \(.message)"' 2>/dev/null)
      [[ -n "$lint" ]] && report+="credo, on lines you changed in ${file#"$dir"/}:"$'\n'"$lint"$'\n'
    fi
  else
    why=$(printf '%s' "$out" | jq -r '.failures[0].message // empty' 2>/dev/null | sed 's/; mix format failed:.*//')
    problems+="${file#"$dir"/} was written but ${why:-could not be formatted}"$'\n'
  fi
  rm -f "$before"
done <<<"$files"

if [[ -n "$problems" ]]; then
  printf '%s' "$problems" >&2
  exit 2
fi

if [[ -n "$report" ]]; then
  jq -n --arg ev "$event" --arg ctx "${report}${moved:+Edit against these lines as they are now, not as you last read them.}" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
fi
exit 0
