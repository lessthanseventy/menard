# Planted, on the copy a run starts from (Tlön's own repo is never touched), past Tlön's own tests:
# the switcher's matcher scores right and its filter quietly drops what scores zero or below when
# the query is one or two letters, which a thread's initials far down a long path do (`rr` against
# `Machine · Tlön · rail redesign` scores -5; with no project in the path, +2). The symptom points
# at search; the fault is the floor. Tlön's own precommit, both apps, is green with it (checked
# 2026-09-26 by reference/validate.py, 922 console tests).
# (Earlier plants, both caught by Tlön's suite: the title left out of a row's text, by
# picker_test.exs:57; the floor for every query, by picker_test.exs:82.)
set -euo pipefail
python3 - <<'PY'
import sys
def plant(path, old, new):
    s = open(path).read()
    if s.count(old) != 1:
        sys.exit(f"setup: {path} no longer holds the line to plant over")
    open(path, "w").write(s.replace(old, new))

# Fuzzy: a short query's match that scores zero or below (a scattered one, far down a long
# subject) is dropped
plant("console/lib/console/fuzzy.ex",
      "        nil -> []\n        score -> [{-score, String.length(text), i, entry}]",
      "        nil -> []\n        score when score <= 0 and byte_size(query) <= 2 -> []\n        score -> [{-score, String.length(text), i, entry}]")
PY
