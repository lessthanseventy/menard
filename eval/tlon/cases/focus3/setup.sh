# Planted, on the copy a run starts from (Tlön's own repo is never touched), past Tlön's own tests:
# the switcher's matcher scores right and its filter quietly drops what scores below zero, which a
# thread's initials far down a long path do. The symptom points at search; the fault is the floor.
# (A second plant, the title left out of a row's text, was caught at once by picker_test.exs:57.)
set -euo pipefail
python3 - <<'PY'
import sys
def plant(path, old, new):
    s = open(path).read()
    if s.count(old) != 1:
        sys.exit(f"setup: {path} no longer holds the line to plant over")
    open(path, "w").write(s.replace(old, new))

# Fuzzy: a match that scores below zero (a scattered one, far down a long subject) is dropped
plant("console/lib/console/fuzzy.ex",
      "        nil -> []\n        score -> [{-score, String.length(text), i, entry}]",
      "        score when is_integer(score) and score > 0 -> [{-score, String.length(text), i, entry}]\n        _ -> []")
PY
