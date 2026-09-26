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
# one mark per call: per session, a second Bash call in flight moved the first one's mark past the
# files it had written, and they went unformatted
call=$(jq -r '.tool_use_id // "none"' <<<"$payload")
mark="${TMPDIR:-/tmp}/menard-format-${session//[^A-Za-z0-9_-]/}-${call//[^A-Za-z0-9_-]/}"

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
  rm -f "$mark"
  # what git ignores is no one's edit: menard's own test run writes fixtures under tmp/, broken on
  # purpose, and each was named as a file the agent wrote and could not format
  # -z: without it git prints a path with a non-ASCII byte quoted and escaped, which matches nothing
  ignored=$(tr '\n' '\0' <<<"$files" | git -C "$root" check-ignore -z --stdin 2>/dev/null | tr '\0' '\n')
  [[ -n "$ignored" ]] && files=$(grep -vxF -f <(printf '%s\n' "$ignored") <<<"$files")
else
  files=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' <<<"$payload")
fi
[[ -n "$files" ]] || exit 0

report="" problems="" moved="" written=""
while IFS= read -r file; do
  case "$file" in *.ex | *.exs) ;; *) continue ;; esac
  [[ -f "$file" ]] || continue
  dir=$(dirname "$(readlink -f "$file")")
  while [[ "$dir" != "/" && ! -f "$dir/mix.exs" ]]; do dir=$(dirname "$dir"); done
  [[ -f "$dir/mix.exs" ]] || continue
  # the Stop hook's list: the projects this session wrote Elixir into, the ones to gate before it ends
  printf '%s\n' "$dir" >>"${TMPDIR:-/tmp}/menard-touched-${session//[^A-Za-z0-9_-]/}"

  written+="$dir|${file#"$dir"/}"$'\n'
  before=$(mktemp)
  cp "$file" "$before"
  # </dev/null: mix reads stdin, and inside this loop took the rest of the file list with it
  out=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run format --in "$dir" "$file" 2>/dev/null </dev/null)

  if [[ "$out" == *'"ok":true'* ]]; then
    # past the two header lines by position: a removed `-- x` reads `--- x`, and a filter took it for one
    change=$(diff -U0 "$before" "$file" | tail -n +3)
    lines=$(wc -l <<<"$change")
    ((lines > 40)) && change=$(head -40 <<<"$change")$'\n'"… $((lines - 40)) more lines of the diff"
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

# MENARD_HOOK_COMPILE (the eval's compile arm): compile each project written into, once, and report
# the compiler's warnings in the files this call wrote. 42 red gates in the operator's sessions were
# warnings-as-errors, found only when the gate ran; an incremental compile on Tlön is under a second.
if [[ -n "${MENARD_HOOK_COMPILE:-}" && -n "$written" ]]; then
  while IFS= read -r dir; do
    out=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run compile --in "$dir" 2>/dev/null </dev/null)
    # compared as text: grep took the path as a regex, and `[x]` in it matched nothing
    mine=$(d=$dir awk -F'|' '$1 == ENVIRON["d"] { print $2 }' <<<"$written" | sort -u)
    warn=$(jq -r '.failures[]? | select(.kind == "warning" or .kind == "error") | "\(.at)|\(.message | split("\n")[0])"' <<<"$out" 2>/dev/null |
      while IFS='|' read -r at msg; do grep -qxF "${at%%:*}" <<<"$mine" && echo "  $at $msg"; done)
    [[ -n "$warn" ]] && report+="the compiler, on files you changed:"$'\n'"$warn"$'\n'
  done < <(cut -d'|' -f1 <<<"$written" | sort -u | grep .)
fi

# exit 2 gives the agent stderr alone: what was reformatted in the same call goes with it, or its next
# Edit on those files is written against a stale read
if [[ -n "$problems" ]]; then
  printf '%s' "$problems" "$report" >&2
  [[ -n "$moved" ]] && echo "Edit against these lines as they are now, not as you last read them." >&2
  exit 2
fi

if [[ -n "$report" ]]; then
  jq -n --arg ev "$event" --arg ctx "${report}${moved:+Edit against these lines as they are now, not as you last read them.}" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
fi
exit 0
