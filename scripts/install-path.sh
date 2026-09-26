#!/usr/bin/env bash
# Put `menard` on PATH: ~/.local/bin/menard → scripts/menard-on-path. Idempotent.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$HOME/.local/bin"
mkdir -p "$dir"
ln -sfn "$repo/scripts/menard-on-path" "$dir/menard"
echo "menard on PATH: $dir/menard → $repo/scripts/menard-on-path"
case ":$PATH:" in *":$dir:"*) ;; *) echo "  $dir is not on your PATH yet: add it" ;; esac
