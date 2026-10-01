#!/usr/bin/env bash
# A replayed-history case from real upstream commits: one session, a step per commit. Before step N
# the run's tree moves to upstream at N's parent (steps/NN/sync.patch, from N-1's parent; the runner's
# sync_upstream), as when the team merged its own version of the last step and more landed; step 1
# starts from the template, which is N=1's parent (`base`). The step is graded on the tests the commit
# itself added or changed (steps/NN/hidden/, as they are at the commit), with the rest of the suite.
# reference/NN.patch is the commit without its tests, for validate.sh only: no run sees it.
# prompt.md is written by hand; upstream.txt (the commit message) is the source it is written from.
# Args: SRC_REPO SUBDIR CASE_DIR SHA... (SUBDIR is the Mix project inside the repo, `.` at its root)
set -euo pipefail
src=$1 sub=$2 case=$3
shift 3
git=(git -C "$src/$sub")
mkdir -p "$case/reference"
prev=$("${git[@]}" rev-parse "$1~1")
echo "$prev" > "$case/base"
n=0
for sha in "$@"; do
  n=$((n + 1))
  nn=$(printf %02d "$n")
  d=$case/steps/$nn
  rm -rf "$d"
  mkdir -p "$d/hidden"
  parent=$("${git[@]}" rev-parse "$sha~1")
  [ "$n" -gt 1 ] && "${git[@]}" diff --binary --relative "$prev" "$parent" -- . > "$d/sync.patch"
  # a rename is a delete and an add: the new file is hidden, the old one goes (`deleted`, which the
  # check removes); left in, it tests what the step moved away
  "${git[@]}" diff --no-renames --name-only --relative --diff-filter=AM "$parent" "$sha" -- test | while read -r f; do
    mkdir -p "$d/hidden/$(dirname "$f")"
    "${git[@]}" show "$sha:./$f" > "$d/hidden/$f"
  done
  "${git[@]}" diff --no-renames --name-only --relative --diff-filter=D "$parent" "$sha" -- test > "$d/deleted"
  [ -s "$d/deleted" ] || rm "$d/deleted"
  "${git[@]}" diff --binary --relative "$parent" "$sha" -- . ':!test' > "$case/reference/$nn.patch"
  "${git[@]}" log -1 --format='%h %ad%n%n%B' --date=short "$sha" > "$d/upstream.txt"
  ln -sfn ../../../../check.sh "$d/check.sh"
  prev=$parent
done
echo "$n steps, base $(cut -c1-8 "$case/base")"
