# Planted, on the copy a run starts from (ex_riverside's own repo is never touched), past the
# project's own suite and precommit (594 tests, green with it): the dashboard's review queue lists a
# submission by a user at the reviewer's own level, which the review page then refuses (the
# strict-above rule in Permissions is right). The symptom is a permission bounce; the fault is the
# queue's comparison. count_pending_submissions_for/1 keeps the right rule (nothing calls it).
set -euo pipefail
python3 - <<'PY'
import sys
def plant(path, old, new):
    s = open(path).read()
    if s.count(old) != 1:
        sys.exit(f"setup: {path} no longer holds the line to plant over")
    open(path, "w").write(s.replace(old, new))

plant("lib/ex_riverside/events.ex",
      "    |> where([e, u], e.status == :submitted and u.role_level < ^reviewer_level)\n",
      "    |> where([e, u], e.status == :submitted and u.role_level <= ^reviewer_level)\n")
PY
