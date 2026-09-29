#!/usr/bin/env python3
"""The desk case's graders, validated both ways.

    MENARD_EVAL_WORK=/tmp/desk-eval python3 eval/helpdesk/cases/desk/reference/validate.py [NAME ...]

NN.patch is the reference app as it stands after step NN, a whole diff from the template. Each
row is a fresh workspace, a patch applied, for a wrong answer one change made on top of it (text
swapped in a file, each swap found exactly once), and the step's check run on a copy as the runner
runs it. The verdict is held against what is expected: a right answer passes, and each wrong one,
the kind a session plausibly makes, fails. One line per row, `MISMATCH` where a grader no longer
tells the two apart, and exit 1 if any. Needs the built template (eval/helpdesk/build.sh).

No model runs here, and nothing here reaches a run: the runner copies the template alone.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASE = HERE.parent
EVAL = CASE.parents[2]
sys.path.insert(0, str(EVAL))
import run  # noqa: E402

TICKETS = "lib/desk/tickets.ex"
SLA = "lib/desk/sla.ex"

# (step, name, patch, [(file, old, new)], passes?)
ROWS = [
    ("01", "template", None, [], False),
    ("01", "tickets", "01", [], True),
    ("01", "high-before-urgent", "01", [(TICKETS, "WHEN 'urgent' THEN 0 WHEN 'high' THEN 1", "WHEN 'urgent' THEN 1 WHEN 'high' THEN 0")], False),
    ("01", "any-at-sign", "01", [("lib/desk/tickets/ticket.ex", "~r/^[^\\s@]+@[^\\s@]+$/", "~r/@/")], False),
    ("02", "flow", "02", [], True),
    ("02", "new-to-resolved", "02", [(TICKETS, "    new: [:open],", "    new: [:open, :resolved],")], False),
    ("02", "reopened-keeps-resolved-at", "02", [(TICKETS, "  defp times(:open), do: [resolved_at: nil]\n", "")], False),
    ("03", "staff", "03", [], True),
    ("03", "load-counts-finished", "03", [(TICKETS, "        where: t.status in ^@at_work and not is_nil(t.assignee_id),",
                                           "        where: not is_nil(t.assignee_id),")], False),
    ("04", "comments", "04", [], True),
    ("04", "every-answer-is-the-first", "04", [(TICKETS, "  defp answered(%Ticket{first_response_at: nil} = ticket, %Comment{",
                                                "  defp answered(%Ticket{} = ticket, %Comment{")], False),
    ("04", "notes-move-tickets", "04", [(TICKETS, "      {%Comment{internal: true}, _} ->\n        ticket\n\n", "")], False),
    ("05", "sla", "05", [], True),
    ("05", "closing-rolls-over", "05", [(SLA, "    if seconds <= left,", "    if seconds < left,")], False),
    ("05", "weekends-count", "05", [(SLA, "      Date.day_of_week(date) > 5 -> next_morning(date)\n", "")], False),
    ("06", "pages", "06", [], True),
    ("06", "every-move-offered", "06", [("lib/desk_web/live/ticket_live/show.ex", "      moves: Tickets.allowed_transitions(ticket.status),",
                                         "      moves: [:open, :pending, :resolved, :closed],")], False),
    ("07", "api", "07", [], True),
    ("07", "csv-with-lf", "07", [("lib/desk_web/controllers/ticket_controller.ex", '"\\r\\n"]', '"\\n"]')], False),
    ("07", "csv-quotes-doubled-not", "07", [("lib/desk_web/controllers/ticket_controller.ex",
                                             'String.replace(text, "\\"", "\\"\\"")', "text")], False),
    ("07", "export-after-the-page", "07", [("lib/desk_web/router.ex", '    get "/tickets/export.csv", TicketController, :export\n', ""),
                                           ("lib/desk_web/router.ex", '    live "/tickets/:id", TicketLive.Show\n',
                                            '    live "/tickets/:id", TicketLive.Show\n    get "/tickets/export.csv", TicketController, :export\n')], False),
    ("08", "actor", "08", [], True),
    ("08", "transition-kept", "08", [(TICKETS, "  def list_events(", "  def transition(ticket, to), do: change_status(ticket, to, :system)\n\n  def list_events(")], False),
    ("08", "comments-move-as-system", "08", [(TICKETS, "        move!(ticket, :open, :requester)", "        move!(ticket, :open, :system)")], False),
    ("09", "unsplit", "08", [], False),
    ("09", "split", "09", [], True),
    ("09", "a-function-dropped", "09", [(TICKETS, "  defdelegate list_events(ticket), to: Flow\n", "")], False),
]


def swap(ws, file, old, new):
    path = ws / file
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"{file} holds {text.count(old)} of, not one: {old!r}")
    path.write_text(text.replace(old, new))


def validate(step, name, patch, swaps, passes):
    ws = run.WORK / "bench" / f"desk.validate.{name}"
    run.prepare(CASE, ws, "without")
    try:
        if patch:
            subprocess.run(["git", "apply", "--index", str(HERE / f"{patch}.patch")], cwd=ws, check=True)
        for file, old, new in swaps:
            swap(ws, file, old, new)
        snap = ws.parent / f"{ws.name}.check"
        shutil.rmtree(snap, ignore_errors=True)
        subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(snap)], check=True)
        code, out = run.check(CASE / "steps" / step, snap, dict(os.environ))
        shutil.rmtree(snap, ignore_errors=True)
    finally:
        shutil.rmtree(ws, ignore_errors=True)
    ok = (code == 0) == passes
    last = next((l for l in reversed(out.strip().splitlines()) if l.strip()), "")
    print(f"{'ok      ' if ok else 'MISMATCH'} step {step} {name}: exit {code}, expected "
          f"{'pass' if passes else 'fail'}; {last[:150]}", flush=True)
    return ok


def main():
    if not run.TEMPLATE.exists():
        sys.exit(f"no template at {run.TEMPLATE}: build it first (TEMPLATE={run.TEMPLATE} bash eval/helpdesk/build.sh)")
    want = set(sys.argv[1:])
    rows = [r for r in ROWS if not want or r[1] in want]
    results = [validate(*r) for r in rows]
    print(f"{sum(results)} of {len(results)} as expected")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
