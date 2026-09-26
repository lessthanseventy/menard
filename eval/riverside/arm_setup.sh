#!/usr/bin/env bash
# ex_riverside as each arm would find it. The project has no door to menard and no word of it (its
# notes send the gate through `mix precommit`), so arm A gets the tree exactly as the template has
# it, and an arm with menard needs nothing beyond its plugin: the session note (hooks/session-run.sh)
# names the plugin's own bin/menard. What this does is hold that line: a workspace for arm A that
# mentions menard anywhere fails the run before it starts. Args: ARM PLUGIN_DIR; runs in the workspace.
set -euo pipefail
arm=$1
if [[ "$arm" == A ]]; then
  case "$PWD" in *[Mm]enard*) echo "arm_setup: arm A's workspace path names menard: $PWD" >&2; exit 1 ;; esac
  found=$(grep -rIil menard . --exclude-dir=deps --exclude-dir=_build --exclude-dir=node_modules || true)
  if [[ -n "$found" ]]; then
    echo "arm_setup: arm A's workspace mentions menard:" >&2
    echo "$found" >&2
    exit 1
  fi
fi
