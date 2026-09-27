#!/usr/bin/env bash
# PostToolUse on Edit|Write|MultiEdit, and Pre/PostToolUse(+Failure) on Bash: every Elixir file an
# edit or a shell command wrote is formatted with its own project's formatter, plugins included.
# What the formatter changed goes back to the agent as context, so its next Edit is written
# against the file as it is, not as it read it (`999999` became `999_999` under an agent in the
# eval, and its next Edit missed). A file that does not parse is named, with the compiler's why.
#
# The eval (bench5): this alone gave menard's clean output, at no-menard's cost.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event=$(jq -r '.hook_event_name // empty' <<<"$payload")
tool=$(jq -r '.tool_name // empty' <<<"$payload")
cwd=$(jq -r '.cwd // empty' <<<"$payload")
# one mark per call: per session, a second Bash call in flight moved the first one's mark past the
# files it had written, and they went unformatted
call=$(jq -r '.tool_use_id // "none"' <<<"$payload")
mark="$(session_file format)-${call//[^A-Za-z0-9_-]/}"

# The agent's own gate, green, is the stop gate's too: riverside1's stop gate ran 12s at every step
# to re-check what the agent had just checked, and never refused one. `tail` hides the gate's exit
# code, so its output decides: the tests' summary at 0 failures is the last step of a precommit
# alias, which stops at its first failing step, so every step before it passed. Anything red in the
# output keeps the stop gate on; so does a write after this (the count moves on).
if [[ "$tool" == "Bash" && "$event" == "PostToolUse" ]]; then
  cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
  out=$(jq -r '.tool_response.stdout // empty' <<<"$payload")
  touched=$(session_file touched)
  if [[ -s "$touched" && "$cmd" =~ (mix[[:space:]]+precommit|menard[^\|\;\&]*[[:space:]]run[[:space:]]+check|mix[[:space:]]+menard\.run[[:space:]]+check) ]] &&
    grep -qE '(^|[^0-9])0 failures|Result: ([0-9]+)/\2 passed|"ok":true' <<<"$out" &&
    ! grep -qiE '[1-9][0-9]* failures?|"ok":false|\*\* \(|error|warning' <<<"$out"; then
    wc -l <"$touched" >"$(session_file stop-green)"
  fi
fi

# A write through manos' MCP tools: menard wrote and formatted the file itself, so there is nothing
# to format, but the stop gate checks the projects on this list, and an MCP write went through no
# Edit, Write or Bash (riverside2: a session of manos writes read as "nothing written"). Reads
# (`get`, `list`, `refs`; `outline`, `find`, `run`) write nothing.
if [[ "$tool" == mcp__*menard__* ]]; then
  verb=$(jq -r '.tool_input.verb // empty' <<<"$payload")
  case "${tool##*__}" in outline | find | run) exit 0 ;; esac
  case "$verb" in get | list | refs) exit 0 ;; esac
  root=${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ "$file" == /* ]] || file="$root/$file"
    dir=$(dirname "$file")
    while [[ "$dir" != "/" && ! -f "$dir/mix.exs" ]]; do dir=$(dirname "$dir"); done
    [[ -f "$dir/mix.exs" ]] && printf '%s\n' "$dir" >>"$(session_file touched)"
  done < <(jq -r '.tool_input | (.file, .to, (.files // [])[]?) // empty | strings' <<<"$payload")
  exit 0
fi

# A shell command: a mark before it, and after it every Elixir file newer than the mark
if [[ "$tool" == "Bash" && "$event" == "PreToolUse" ]]; then
  touch "$mark"
  exit 0
fi

if [[ "$tool" == "Bash" ]]; then
  root=${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}
  [[ -f "$mark" ]] || exit 0
  files=$(find "$root" "${prune[@]}" \
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

# the files by project, for one menard start per project: one per file (format 0.46s, credo 1.2s)
# took ~170s over a 100-file change, past the hook's 60s, and the agent heard nothing
declare -A of=()
while IFS= read -r file; do
  case "$file" in *.ex | *.exs) ;; *) continue ;; esac
  [[ -f "$file" ]] || continue
  dir=$(dirname "$(readlink -f "$file")")
  while [[ "$dir" != "/" && ! -f "$dir/mix.exs" ]]; do dir=$(dirname "$dir"); done
  [[ -f "$dir/mix.exs" ]] || continue
  of[$dir]+="$file"$'\n'
done <<<"$files"

report="" problems="" moved="" written=""
for dir in "${!of[@]}"; do
  mapfile -t list <<<"${of[$dir]%$'\n'}"
  # what git wrote (a checkout, a reset, a new worktree, a popped stash) is content its repo already
  # holds: no one's edit, and none to format. Read off the command, `cd D && git …` was taken for an
  # edit of every file git checked out, and `git … && sed …` hid the sed's. An edit makes new content;
  # one staged in the same command is left as it was staged.
  if [[ "$tool" == "Bash" ]]; then
    held=$(printf '%s\n' "${list[@]}" | git -C "$dir" hash-object --stdin-paths 2>/dev/null |
      git -C "$dir" cat-file --batch-check 2>/dev/null)
    mapfile -t held <<<"$held"
    # a line per file, else nothing to go by (no repo): format them all
    if [[ -n "${held[0]}" ]] && ((${#held[@]} == ${#list[@]})); then
      new=()
      for i in "${!list[@]}"; do [[ "${held[$i]}" == *" missing" ]] && new+=("${list[$i]}"); done
      list=("${new[@]}")
      ((${#list[@]})) || continue
    fi
  fi
  # the Stop hook's list: the projects this session wrote Elixir into, the ones to gate before it ends
  printf '%s\n' "$dir" >>"$(session_file touched)"
  before=$(mktemp -d)
  for i in "${!list[@]}"; do cp "${list[$i]}" "$before/$i"; done
  # </dev/null: mix reads stdin, and inside a loop took the rest of its list with it
  reply=$("$menard" run format --in "$dir" "${list[@]}" 2>/dev/null </dev/null | tail -n1)
  # the files that did not format, as the reply names them (relative to the project)
  failed=$(jq -r '.failures[]?.at' <<<"$reply" 2>/dev/null)
  why=$(jq -r '.failures[]? | "\(.at) was written but \(.message)"' <<<"$reply" 2>/dev/null)
  [[ -n "$why" ]] && problems+="$why"$'\n'
  lint=()
  for i in "${!list[@]}"; do
    file=${list[$i]}
    rel=${file#"$dir"/}
    written+="$dir|$rel"$'\n'
    # no reply at all: menard did not start, and nothing was formatted
    if ! jq -e 'has("ok")' <<<"$reply" >/dev/null 2>&1; then
      problems+="$rel was written but could not be formatted"$'\n'
      continue
    fi
    grep -qxF -- "$rel" <<<"$failed" && continue
    lint+=("$rel")
    # past the two header lines by position: a removed `-- x` reads `--- x`, and a filter took it for one
    change=$(diff -U0 "$before/$i" "$file" | tail -n +3)
    lines=$(wc -l <<<"$change")
    ((lines > 40)) && change=$(head -40 <<<"$change")$'\n'"… $((lines - 40)) more lines of the diff"
    [[ -n "$change" ]] && report+="$rel was reformatted:"$'\n'"$change"$'\n' && moved=1
  done
  rm -rf "$before"
  # credo on what this session changed in the files, when the project lints with it: found at write
  # time it is one edit; found in CI it is a round trip. Its default level; --strict is the project's.
  if ((${#lint[@]})) && { [[ -d "$dir/deps/credo" ]] || grep -qs '"credo":' "$dir/mix.lock"; }; then
    found=$("$menard" run credo --in "$dir" --changed "${lint[@]}" 2>/dev/null </dev/null | tail -n1 |
      jq -r '.failures[]? | "  \(.at) \(.message)"' 2>/dev/null)
    [[ -n "$found" ]] && report+="credo, on lines you changed:"$'\n'"$found"$'\n'
  fi
done

# MENARD_HOOK_COMPILE (the eval's compile arm): compile each project written into, once, and report
# the compiler's warnings in the files this call wrote. 42 red gates in the operator's sessions were
# warnings-as-errors, found only when the gate ran; an incremental compile on Tlön is under a second.
if [[ -n "${MENARD_HOOK_COMPILE:-}" && -n "$written" ]]; then
  while IFS= read -r dir; do
    out=$("$menard" run compile --in "$dir" 2>/dev/null </dev/null)
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
