# Planted bugs, each on the copy a run starts from (Tlön's own repo is never touched), each a line a
# real change could have made, and each past Tlön's own tests: only the step's hidden test sees it.
set -euo pipefail
python3 - <<'PY'
import sys
def plant(path, old, new):
    s = open(path).read()
    if s.count(old) != 1:
        sys.exit(f"setup: {path} no longer holds the line to plant over")
    open(path, "w").write(s.replace(old, new))

# 1. Attention: a Claude Code dialog counts as waiting only while its cursor is on option 1
plant("server/lib/server/attention.ex",
      'if length(matches) >= 2 and Enum.any?(matches, &(elem(&1, 0) == "❯")) and is_binary(question) do',
      'if length(matches) >= 2 and elem(hd(matches), 0) == "❯" and is_binary(question) do')

# 2. Commits: a thread's commits read from the checked-out branch only, not every ref
plant("server/lib/server/commits.ex",
      'args = ["log", "--all", "--grep=',
      'args = ["log", "--grep=')
PY
