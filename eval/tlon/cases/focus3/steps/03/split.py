"""Is cockpit.ex split, or only shorter? Measured in code lines (blank and comment lines aside)
against the eval-base tag, from the repo root:

- cockpit.ex keeps at most 60% of its code lines;
- at least two NEW modules under lib/console/cockpit/, each at least 10% of cockpit.ex's old code
  lines, and each named in cockpit.ex (one dump module, or a stub beside one, is not a split);
- the code lines of cockpit.ex and every module under lib/console/cockpit/ together are within
  10% of before: moved, not deleted.

Exit 1 with a FAIL line on the first miss; the numbers either way.
"""

import re
import subprocess
import sys
from pathlib import Path

COCKPIT = "console/lib/console/cockpit.ex"
SUB = "console/lib/console/cockpit"
KEEP, EACH, MOVED = 0.6, 0.1, 0.1


def code_lines(text):
    return sum(1 for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#"))


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def module_of(text):
    m = re.search(r"^defmodule\s+([\w.]+)", text, re.M)
    return m.group(1) if m else None


def main():
    base_cockpit = code_lines(git("show", f"eval-base:{COCKPIT}"))
    base_subs = {p: code_lines(git("show", f"eval-base:{p}"))
                 for p in git("ls-tree", "-r", "--name-only", "eval-base", SUB).split()}
    cockpit = Path(COCKPIT).read_text()
    now_cockpit = code_lines(cockpit)
    now_subs = {str(p): code_lines(p.read_text()) for p in sorted(Path(SUB).rglob("*.ex"))}
    # a name in cockpit.ex outside its comments: the module's full name, or its last segment aliased
    code = "\n".join(l for l in cockpit.splitlines() if not l.lstrip().startswith("#"))
    new = {}
    for p, n in now_subs.items():
        if p in base_subs:
            continue
        mod = module_of(Path(p).read_text())
        used = mod and (mod in code or re.search(rf"\b{re.escape(mod.rsplit('.', 1)[-1])}\b", code))
        new[p] = (n, mod, bool(used))
    substantial = [p for p, (n, _, used) in new.items() if used and n >= EACH * base_cockpit]
    base_total, now_total = base_cockpit + sum(base_subs.values()), now_cockpit + sum(now_subs.values())
    print(f"cockpit.ex: {now_cockpit} code lines, was {base_cockpit}; new modules: "
          + (", ".join(f"{Path(p).name} {n}{'' if used else ' (unused)'}" for p, (n, _, used) in new.items()) or "none")
          + f"; cockpit.ex and lib/console/cockpit/ together: {now_total}, was {base_total}")
    if now_cockpit > KEEP * base_cockpit:
        sys.exit(f"FAIL: cockpit.ex keeps {now_cockpit} of {base_cockpit} code lines (at most {KEEP:.0%} for a split)")
    if len(substantial) < 2:
        sys.exit(f"FAIL: {len(substantial)} new module(s) under lib/console/cockpit/ of at least {int(EACH * base_cockpit)} "
                 f"code lines that cockpit.ex uses (a split has at least 2)")
    if not (1 - MOVED) * base_total <= now_total <= (1 + MOVED) * base_total:
        sys.exit(f"FAIL: {base_total} code lines became {now_total} (a split moves them: within {MOVED:.0%})")


if __name__ == "__main__":
    main()
