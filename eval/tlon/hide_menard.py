"""Tlön as the control arm must find it: no menard to run and no word that there is one to run.

    hide_menard.py TEMPLATE DOOR_DIR

Tlön's docs, tasks and scripts tell an agent menard exists and how to reach it; arm A must not know
(the operator's rule: a control arm that knows the tool can go looking for it). Every passage that
teaches or opens menard goes; the task door (tasks/menard.toml) is kept aside in DOOR_DIR for
arm_setup.sh to put back in the arms that have menard. Each cut asserts its text is still there,
so a Tlön change fails the build instead of leaving a mention behind.

What stays, the same in every arm, because it is Tlön's product and not a way to menard: the
server's dependency on the library (server/mix.exs, mix.lock, deps/, and Server.Source.Tools, the
coworkers' source verbs that call it), and test data or seeds naming a sibling project "menard".
eval/tests/test_menard_hidden.py holds that line.
"""

import shutil
import sys
from pathlib import Path


def cut(path, old, new=""):
    text = path.read_text()
    if text.count(old) != 1:
        sys.exit(f"hide_menard: {path} no longer holds, exactly once:\n{old}")
    path.write_text(text.replace(old, new))


def main(template, door):
    t, door = Path(template), Path(door)
    door.mkdir(parents=True, exist_ok=True)
    shutil.move(str(t / "tasks/menard.toml"), str(door / "menard.toml"))
    (t / "scripts/menard.sh").unlink()

    cut(t / "mise.toml", ', "tasks/menard.toml"')
    cut(t / "mise.toml",
        "(server, console, adapters, pi, menard). menard's live HERE and\n"
        "# not beside the tool: menard is its own repo (~/projects/menard), and which menard the server\n"
        "# runs (its mix.lock pin) is tlon's business, not menard's.\n",
        "(server, console, adapters, pi).\n")
    cut(t / "server/mix.exs",
        "      # Menard (hex.pm/packages/menard): AST-aware source edits + introspection on Sourceror; the\n"
        "      # coworkers' source verbs (Server.Source.Tools) call it — a runtime dep. From hex, never a\n"
        "      # path: a nix build sees only this checkout. Past 0.5, `Clause.replace_body/5` refuses a whole\n"
        "      # clause (0.5 took it for a rewrite): `clause_edit(:replace, …)` in Server.Source.Tools must\n"
        "      # send one to `Clause.rewrite/5` itself (menard's CHANGELOG, Unreleased).\n")
    cut(t / "docs/manual/tasks.md",
        "## menard\n\n| verb | does |\n|---|---|\n"
        "| `menard:check` | menard: its own gate — format + warnings-as-errors + tests |\n\n")
    manual = t / "docs/manual/tasks.md"
    lines = manual.read_text().splitlines(keepends=True)
    rows = [l for l in lines if l.startswith("| `menard` |")]
    if len(rows) != 1:
        sys.exit(f"hide_menard: {manual} no longer holds one `menard` task row")
    manual.write_text("".join(l for l in lines if l not in rows))

    cut(t / "adapters/README.md",
        "menard's pi adapter (the guard + format-on-save) is the exception — it ships from\n"
        "~/projects/menard, a standalone repo, and ficciones only points pi at it.\n")
    readme = t / "adapters/README.md"
    text = readme.read_text()
    a = text.find("  menard/             (in ~/projects/menard)")
    b = text.find("  lsp/ ", a)
    if a < 0 or b < 0:
        sys.exit(f"hide_menard: {readme} no longer lists menard/ before lsp/")
    readme.write_text(text[:a] + text[b:])
    cut(t / "adapters/AGENTS.md", "the six repo extensions", "the five repo extensions")
    cut(t / "adapters/AGENTS.md", ", and menard's\n  `pi/extension.ts` (shipped from ~/projects/menard, wired here by the flake).",
        ".")
    cut(t / "adapters/AGENTS.md", " menard's pi adapter\n  is checked in its own repo (its `test` task, in ~/projects/menard).", "")
    cut(t / "adapters/lsp/AGENTS.md", "  menard already formats on save (the pi/extension.ts `tool_result` hook). LSP gives what",
        "  LSP gives what")
    cut(t / "tasks/adapters.toml",
        "# menard's pi adapter lives in ~/projects/menard (standalone repo). Its gate is\n"
        "# `mise run test` there (bun test in pi/). No tlon-side package to check.\n\n")


if __name__ == "__main__":
    main(*sys.argv[1:3])
