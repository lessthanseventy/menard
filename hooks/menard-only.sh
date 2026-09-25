#!/usr/bin/env bash
# PreToolUse hook, the Claude Code adapter for `menard guard` (docs/adapters.md): an Elixir module
# is edited with menard's verbs, not with Edit/Write. The decision and the message live in the verb,
# which every harness shares; this file only reads Claude Code's payload and turns the verb's exit 2
# into Claude Code's "block".
#
# A rule the agent has to remember is a rule it breaks, which is the argument for a hook rather
# than a note in AGENTS.md.
#
# Edit/Write only, NOT Bash. A shell command carries no structured target, so deciding whether it
# writes to an Elixir file means pattern-matching the command text — and that fires on a command
# that merely QUOTES the pattern. A guard that blocks innocent commands gets switched off.
set -uo pipefail

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null) || exit 0

case "$tool" in
  Edit | MultiEdit | Write | NotebookEdit)
    file=$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null)
    # Only an .ex/.exs can be refused, and this hook runs on EVERY edit: skip the verb's ~0.6s start
    # for the rest. The real decision is the verb's.
    case "$file" in *.ex | *.exs) ;; *) exit 0 ;; esac
    [[ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/menard" ]] || exit 0
    "$CLAUDE_PLUGIN_ROOT/bin/menard" guard "$file" </dev/null
    status=$?
    # 2 is the refusal; anything else (menard failing to start) must never block an edit
    ((status == 2)) && exit 2
    ;;
esac
exit 0
