#!/usr/bin/env bash
# Arm H's one hook: after an Edit/Write of an Elixir file, format it with its own project's
# formatter (plugins included) and, when it does not parse or cannot be formatted, say why to the
# agent (PostToolUse exit 2 puts stderr in front of the model). No tools, no guard: the question is
# whether this alone gives menard's clean output at plain Edit's cost.
set -uo pipefail

file=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -n "$file" && -f "$file" ]] || exit 0
case "$file" in *.ex | *.exs) ;; *) exit 0 ;; esac

dir=$(dirname "$(readlink -f "$file")")
while [[ "$dir" != "/" && ! -f "$dir/mix.exs" ]]; do dir=$(dirname "$dir"); done
[[ -f "$dir/mix.exs" ]] || exit 0

out=$("$CLAUDE_PLUGIN_ROOT/bin/menard" run format --in "$dir" "$file" 2>/dev/null)
[[ "$out" == *'"ok":true'* ]] && exit 0

# the reason, without the stack mix prints after it
why=$(printf '%s' "$out" | jq -r '.failures[0].message // empty' 2>/dev/null | sed 's/; mix format failed:.*//')
echo "${file##*/} was written but ${why:-could not be formatted}" >&2
exit 2
