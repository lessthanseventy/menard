"""Is events.ex split, or only shorter? Measured in code lines (blank and comment lines aside)
against the eval-base tag, from the repo root:

- events.ex keeps at most 60% of its code lines;
- at least two NEW modules under lib/ex_riverside/events/, each at least 10% of events.ex's old
  code lines, and each named in events.ex (one dump module, or a stub beside one, is not a split);
- the code lines of events.ex and every module under lib/ex_riverside/events/ together are within
  10% of events.ex's old code lines below the old total (moved, not deleted) and 30% above it (a
  facade of delegates and the new modules' heads are new lines).

Exit 1 with a FAIL line on the first miss; the numbers either way.
"""

import re
import subprocess
import sys
from pathlib import Path

EVENTS = "lib/ex_riverside/events.ex"
SUB = "lib/ex_riverside/events"
KEEP, EACH, LOST, GROWN = 0.6, 0.1, 0.1, 0.3


def code_lines(text):
    return sum(1 for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#"))


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def module_of(text):
    m = re.search(r"^defmodule\s+([\w.]+)", text, re.M)
    return m.group(1) if m else None


def main():
    base_events = code_lines(git("show", f"eval-base:{EVENTS}"))
    base_subs = {p: code_lines(git("show", f"eval-base:{p}"))
                 for p in git("ls-tree", "-r", "--name-only", "eval-base", SUB).split()}
    events = Path(EVENTS).read_text()
    now_events = code_lines(events)
    now_subs = {str(p): code_lines(p.read_text()) for p in sorted(Path(SUB).rglob("*.ex"))}
    # a name in events.ex outside its comments: the module's full name, or its last segment aliased
    code = "\n".join(l for l in events.splitlines() if not l.lstrip().startswith("#"))
    new = {}
    for p, n in now_subs.items():
        if p in base_subs:
            continue
        mod = module_of(Path(p).read_text())
        used = mod and (mod in code or re.search(rf"\b{re.escape(mod.rsplit('.', 1)[-1])}\b", code))
        new[p] = (n, mod, bool(used))
    substantial = [p for p, (n, _, used) in new.items() if used and n >= EACH * base_events]
    base_total, now_total = base_events + sum(base_subs.values()), now_events + sum(now_subs.values())
    print(f"events.ex: {now_events} code lines, was {base_events}; new modules: "
          + (", ".join(f"{Path(p).name} {n}{'' if used else ' (unused)'}" for p, (n, _, used) in new.items()) or "none")
          + f"; events.ex and lib/ex_riverside/events/ together: {now_total}, was {base_total}")
    if now_events > KEEP * base_events:
        sys.exit(f"FAIL: events.ex keeps {now_events} of {base_events} code lines (at most {KEEP:.0%} for a split)")
    if len(substantial) < 2:
        sys.exit(f"FAIL: {len(substantial)} new module(s) under lib/ex_riverside/events/ of at least {int(EACH * base_events)} "
                 f"code lines that events.ex uses (a split has at least 2)")
    if not base_total - LOST * base_events <= now_total <= base_total + GROWN * base_events:
        sys.exit(f"FAIL: {base_total} code lines became {now_total} (a split moves them: at most {int(LOST * base_events)} "
                 f"fewer, {int(GROWN * base_events)} more)")


if __name__ == "__main__":
    main()
