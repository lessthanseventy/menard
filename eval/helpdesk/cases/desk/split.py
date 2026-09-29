#!/usr/bin/env python3
"""Step 09: is Desk.Tickets split for real? Run in the workspace.

No line count of before is to be had (the module is the session's own, of whatever size it made
it), so the measure is the shape after: the code that is about tickets lives under
lib/desk/tickets/ in at least two modules of substance besides the schemas, lib/desk/tickets.ex
names them, and it is the smaller part of the whole. Code lines: not blank, not a comment.
"""
import re
import sys
from pathlib import Path

FACADE = Path("lib/desk/tickets.ex")
PARTS = Path("lib/desk/tickets")
SUBSTANCE = 25   # code lines, for a module to count as one the split made
SHARE = 0.6      # of the code, at most, left in the facade: the reference split leaves 40%


def code_lines(path):
    return [l for l in path.read_text().splitlines() if l.strip() and not l.strip().startswith("#")]


def fail(why):
    print(f"FAIL: split: {why}")
    sys.exit(1)


if not FACADE.exists():
    fail(f"{FACADE} is gone: Desk.Tickets is what ties the parts together")
if not PARTS.is_dir():
    fail(f"no {PARTS}/")

facade = FACADE.read_text()
parts = {}
for path in sorted(PARTS.rglob("*.ex")):
    source = path.read_text()
    if re.search(r"^\s*use Ecto\.Schema\b", source, re.M):
        continue
    module = re.search(r"^\s*defmodule\s+([\w.]+)", source, re.M)
    if not module:
        continue
    name = module.group(1)
    short = name.split(".")[-1]
    used = re.search(rf"\b{re.escape(name)}\b", facade) or re.search(
        rf"alias\s+Desk\.Tickets\.(\{{[^}}]*\b{short}\b[^}}]*\}}|{short}\b)", facade)
    publics = len(re.findall(r"^\s*def\s+\w", source, re.M))
    parts[path] = {"lines": len(code_lines(path)), "used": bool(used), "publics": publics}

real = {p: d for p, d in parts.items() if d["lines"] >= SUBSTANCE and d["used"] and d["publics"] >= 2}
here = len(code_lines(FACADE))
there = sum(d["lines"] for d in parts.values())
print(f"tickets.ex: {here} code lines; under {PARTS}/: " + (", ".join(
    f"{p.name} {d['lines']}" + ("" if d["used"] else " (unused)") for p, d in parts.items()) or "nothing but schemas"))
if len(real) < 2:
    fail(f"{len(real)} module(s) of substance that Desk.Tickets uses, 2 needed "
         f"({SUBSTANCE} code lines and two public functions each)")
if here > SHARE * (here + there):
    fail(f"tickets.ex still holds {here} of {here + there} code lines, more than {int(SHARE * 100)}%")
