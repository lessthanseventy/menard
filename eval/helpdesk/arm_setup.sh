#!/usr/bin/env bash
# The app as each arm finds it: the same tree. The template has no word of menard, and an arm with
# it needs nothing beyond its plugin. What this does is hold that line: a workspace for the arm
# without that mentions menard anywhere fails the run before it starts. Args: ARM PLUGIN_DIR.
set -euo pipefail
arm=$1
if [[ "$arm" == without ]]; then
  case "$PWD" in *[Mm]enard*) echo "arm_setup: the workspace path names menard: $PWD" >&2; exit 1 ;; esac
  found=$(grep -rIil menard . --exclude-dir=deps --exclude-dir=_build --exclude-dir=node_modules || true)
  if [[ -n "$found" ]]; then
    echo "arm_setup: the workspace mentions menard:" >&2
    echo "$found" >&2
    exit 1
  fi
fi
